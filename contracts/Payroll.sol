pragma solidity 0.4.19;

import "./PayrollInterface.sol";
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import "tokens/contracts/HumanStandardToken.sol";

/**
 * @title Payroll contract for paying employees
 * @author Cory VanHooser
 */
contract Payroll is PayrollInterface, Ownable {
  /*************
   * VARIABLES *
   *************/

  /**
   * EMPLOYEES
   */
  struct Employee {
    uint256 employeeId;
    address accountAddress;
    uint256 yearlyEURSalary;
    address[] allowedTokens;
    address[] tokens;
    uint256[] tokenDistribution;
    uint256 startDate;
    uint256 paydayCalls;
    uint256 tokenAllocationCalls;
  }

  /**
   * CONSTANTS
   */
  uint256 private constant sixMonthsInSeconds = 15780000;
  uint256 private constant oneMonthInSeconds = 2630000;
  address private EURToken; // This would be the contract address of the EURToken

  mapping(uint256 => Employee) private employees; // map of employee id's to their struct
  mapping(address => uint256) private employeeIdLookup; // map of employee accounts to id
  uint256 private lastEmployeeId = 0; // Keep track of the employee id
  uint256 private employeeCount = 0; // Keep track of the number of employees

  /**
   * ORACLE
   */
  address private oracle; // address of the oracle that determines the exchange rate
  mapping(address => uint256) private exchangeRates; // map of tokens and their exchange rate

  /**
   * STATE
   */
  bool private noIssues = true; // Tells us if the escapeHatch has been opened on the contract

  /**
   * PAYROLL TRACKING
   */
  address[] private managedTokenAccts; // The types of tokens that this contract manages
  mapping(address => uint256) private managedTokenIdLookup; // map of tokens to their id
  uint256 private lastManagedTokenId = 0; // Keep track of the last token id

  /**
   * COMPUTED VALUES
   */
  uint256 private yearlyBurnrate = 0; // rolling total of employee salary overhead
  uint256 private payrollRunawayDate = 0; //Date when payroll runs out


  /****************************************
   * CONSTRUCTOR, FALLBACK, AND MODIFIERS *
   ****************************************/

  /**
   * @dev Constructor for payroll
   * @param _oracle the oracle for setting exchange rates
   */
  function Payroll(address _oracle) payable public {
    owner = msg.sender;
    oracle = _oracle;
    managedTokenAccts.push(EURToken); // This is the default payment token
  }

  /**
   * Fallback function
   * @dev If the contract is called without calling a function,
   * the users ether is returned instead of being lost.
   * This is not true in the case of other contracts suiciding and sending funds.
   */
  function() payable public {
    revert();
  }

  /**
   * @dev Modifier for critical failure
   */
  modifier ifNoIssues() {
   require(noIssues);
   _;
  }

  /**
   * @dev Modifier for only allowing oracle access
   */
  modifier onlyOracle() {
    require(msg.sender == oracle);
    _;
  }

  /**
   * @dev Modifier for only allowing employee access
   */
  modifier onlyEmployee() {
    require(employeeIdLookup[msg.sender] > uint256(0));
    _;
  }

  /**********
  * EVENTS *
  **********/
  // Positive log events
  event LogEmployeeAdded(uint256 id, address accountAddress, uint salary);
  event LogEmployeeRemoved(uint256 id);
  event LogEmployeePaid(uint256 id, uint256 amount, uint256 date);
  event LogEmployeeAllocationChanged(uint256 id, address[] tokens, uint256[] allocation);

  event LogFundsRecieved(address, uint256);
  event LogTokensRecieved(address tokenAddress, uint256 amount);
  event LogTokensRecieved(address tokenAddress, uint256 amount, bytes data);

  // Negative log events
  event LogEmployeePayFailure(uint256 id, address tokenAddress, uint amount);
  event LogInsufficientFundsToPayEmployee(uint256 id, address token, uint256 amount);

  event LogFailedToRecieveTokens(address token, uint256 amount);
  event LogFailedToRecieveTokens(address token, uint256 amount, bytes data);
  event LogFailedToRecieveTokensInsufficientFunds(address token, uint256 amount);

  event LogContractnoIssues(uint256 date, address fundHolder, address[] tokens, uint256[] amounts);


  /***********************
   * OWNER ONLY FUNCTIONS
   ***********************/

  /**
    * @dev Adds a new employee to the payroll
    * @param accountAddress Employee to add
    * @param allowedTokens Tokens that the employee is allotted
    * @param yearlyEURSalary Employee yearly salary
    */
  function addEmployee(address accountAddress, address[] allowedTokens, uint256 yearlyEURSalary) public ifNoIssues onlyOwner {
    require(employeeIdLookup[accountAddress] == uint256(0)); // employee should not exist in the current system

    uint256 employeeId = ++lastEmployeeId;

    address[] memory tokens = new address[](1);
    tokens[0] = EURToken;
    uint256[] memory distribution = new uint256[](1);
    distribution[0] = 100;

    // Create a new employee and add him to the map
    employees[employeeId] =
      Employee(
        employeeId,
        accountAddress,
        yearlyEURSalary,
        allowedTokens,
        tokens,
        distribution,
        now,
        1,
        0
      );

    // Add the employee to our idlookup map, and recaluclate the yearly burnrate and adjust the number of employees
    employeeIdLookup[accountAddress] = employeeId;
    yearlyBurnrate += yearlyEURSalary;
    employeeCount++;
    LogEmployeeAdded(employeeId, accountAddress, yearlyEURSalary);
  }

  /**
    * @dev Returns an employee by their id and all their information
    * @param employeeId Employee to return
    * @return all employee attributes
    */
  function getEmployee(uint256 employeeId) constant public ifNoIssues onlyOwner returns (
    address accountAddress,
    uint256 yearlyEURSalary,
    address[] allowedTokens,
    address[] tokens,
    uint256[] distribution
  )
  {
    require(employees[employeeId].accountAddress != address(0));

    return(
      employees[employeeId].accountAddress,
      employees[employeeId].yearlyEURSalary,
      employees[employeeId].allowedTokens,
      employees[employeeId].tokens,
      employees[employeeId].tokenDistribution
    );
  }

  /**
    * @dev Removes an employee from the payroll
    * @param employeeId Employee to remove
    */
  function removeEmployee(uint256 employeeId) public ifNoIssues onlyOwner {
    require(employees[employeeId].accountAddress != address(0));

    // Adjust burnrate and employee count
    yearlyBurnrate -= employees[employeeId].yearlyEURSalary;
    employeeCount--;

    // Remove the employee
    delete employeeIdLookup[employees[employeeId].accountAddress];
    delete employees[employeeId];
    LogEmployeeRemoved(employeeId);
  }

  /**
    * @dev Sets a new salary for an existing employee
    * @param employeeId Employee to set new salary for
    * @param yearlyEURSalary New employee EURSalary
    */
  function setEmployeeSalary(uint256 employeeId, uint256 yearlyEURSalary) public ifNoIssues onlyOwner {
    require(employees[employeeId].accountAddress != address(0));

    Employee storage employee = employees[employeeId];

    // Recalculate the burnrate for both positive and negative salary adjustments
    if(employee.yearlyEURSalary > yearlyEURSalary){
      yearlyBurnrate -= employee.yearlyEURSalary - yearlyEURSalary;
    } else {
      yearlyBurnrate += yearlyEURSalary - employee.yearlyEURSalary;
    }

    // Set the new yearly salary
    employee.yearlyEURSalary = yearlyEURSalary;
  }

  /**
    * @dev Gets the total number of employees
    * @return number of employees
    */
  function getEmployeeCount() constant public ifNoIssues onlyOwner returns (uint256) { return employeeCount; }

  /**
    * @dev Add Token type to be supported by this contract
    * Used so that we can keep track of where all the tokens are in case we need to halt this contract and rescue all funds.
    */
  function addManagedToken(address token) public ifNoIssues onlyOwner {
    require(managedTokenIdLookup[token] != uint256(0));

    uint256 tokenId = ++lastManagedTokenId;
    managedTokenAccts[tokenId] = token;
    managedTokenIdLookup[token] = tokenId;
  }

  /**
    * @dev Add funds to the current contract
    */
  function addFunds() public ifNoIssues payable onlyOwner {
    LogFundsRecieved(msg.sender, msg.value);
  }

  /**
    * @dev Recieve the approval call and transfer tokens to the contract balance
    */
  function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData) public {

    HumanStandardToken hstToken = HumanStandardToken(_tokenContract);

    // Transfer the tokens after recieving approval from the token contract
    if(!hstToken.transferFrom(_from, address(this), _value)){
      LogFailedToRecieveTokens(_tokenContract, _value);
      revert();
    }

    LogTokensRecieved(_tokenContract, _value, _extraData);
  }

  /**
    * @dev Add Tokens to the contract
    * Uses approveAndCall to ensure successful transfer of funds
    */
  function addTokenFunds(address token, uint256 amount) public ifNoIssues onlyOwner {
    require(managedTokenIdLookup[token] != uint256(0) && amount > uint256(0));

    HumanStandardToken hstToken = HumanStandardToken(token);

    // Checking the balance is available
    if(hstToken.balanceOf(msg.sender) >= amount){

      //Use approveAndCall
      if(!hstToken.approveAndCall(msg.sender, amount, msg.data)){
        LogFailedToRecieveTokens(token, amount);
        revert();
      }
    } else {
      LogFailedToRecieveTokensInsufficientFunds(token, amount);
      revert();
    }

    LogTokensRecieved(token, amount);
  }

  /**
    * @dev A way to halt the contract and stop any more damage from being done.
    *
    * This is a quick implementationt to return all the funds to the owner.
    * Improvement: Have funds transfered to another multi-sig contract that could then be called to transfer back funds
    * once this contract is re-enabled. It would stop the owner from having control of all the funds.
    *
    * @return void
    */
  function escapeHatch() public ifNoIssues onlyOwner {
    noIssues = false;

    address[] memory tokensRescued;
    uint256[] memory amountOfTokensRescued;

    //Rescue all the tokens
    for (uint256 i = 0; i < managedTokenAccts.length; i++) {
      if(managedTokenAccts[i] != address(this)){

        // This is an emergency scenario so even with a failure in one transfer,
        // we still want to try to get all tokens out of control of this contract.
        HumanStandardToken hstToken = HumanStandardToken(managedTokenAccts[i]);
        hstToken.approve(msg.sender, hstToken.balanceOf(this));

        // Add to the list of tokens rescued for event
        if(hstToken.transferFrom(address(this), msg.sender, hstToken.balanceOf(this))){
          tokensRescued[i] = managedTokenAccts[i];
          amountOfTokensRescued[i] = hstToken.balanceOf(this);
        }

      }

    }

    // Rescue the Ether
    msg.sender.transfer(this.balance);
    LogContractnoIssues(now, msg.sender, tokensRescued, amountOfTokensRescued);
  }

  /**
    * @dev Calculates the monthly EUR amount spent in salaries
    * @return amount of EUR spent per month on employees
    */
  function calculatePayrollBurnrate() constant public ifNoIssues onlyOwner returns (uint256) { return yearlyBurnrate / 12; }

  /**
    * @dev Calculates the days until the contract can run out of funds
    * @return The amount of days until payroll will runout
    */
  function calculatePayrollRunway() constant public ifNoIssues onlyOwner returns (uint256) {
    uint256 currentEurTotal = 0;

    // Adding up the total tokens and their EUR value to determine how many days
    // we have left based on the currently employee payroll
    for(uint256 i = 0; i < managedTokenAccts.length; i++){
      require(exchangeRates[managedTokenAccts[i]] != uint256(0));

      address managedToken = managedTokenAccts[i];
      if(managedToken != address(this)){

        HumanStandardToken hstToken = HumanStandardToken(managedToken);
        uint256 currentBalance = hstToken.balanceOf(this);
      } else {
        currentEurTotal += this.balance * exchangeRates[managedToken];
      }

      currentEurTotal += currentBalance * exchangeRates[managedToken];
    }

    if(currentEurTotal == 0)
      return uint256(0);

    uint256 daysTillRunaway = (yearlyBurnrate / currentEurTotal * 365);
    return (now / 86400) + daysTillRunaway;
  }

  /**
    * @dev Changes the oracle being used to set exchange rates
    */
  function changeOracle(address _oracle) ifNoIssues onlyOwner public {
    require(oracle != _oracle);
    oracle = _oracle;
  }

  /*************************
   * ORACLE ONLY FUNCTIONS *
   *************************/

  /**
    * @dev Determine token allocation amounts.
    * Exchange rates are done in the lowest denomination
    * @param token Type of token to match against EUR
    * @param exchangeRateEUR Rate that the token trades against EUR
    */
  function setExchangeRate(address token, uint256 exchangeRateEUR) public ifNoIssues onlyOracle {
    exchangeRates[token] = exchangeRateEUR;
  }

  /***************************
   * EMPLOYEE ONLY FUNCTIONS *
   ***************************/

  /**
    * @dev Determine token allocation amounts. (Only callable once every 6 months)
    * This allocates the type of tokens the employee is paid where distribution total must equal 100.
    * @param tokens contract address of the tokens
    * @param distribution the percent the employee recieves per token of their EUR salary
    */
  function determineAllocation(address[] tokens, uint256[] distribution)
  public
  ifNoIssues
  onlyEmployee
  {
    uint256 employeeId = employeeIdLookup[msg.sender];
    Employee storage employee = employees[employeeId];

    // Ensure it has been 6 months since the last the distribution has been set
    require(employee.startDate - now % sixMonthsInSeconds > employee.tokenAllocationCalls);
    require(tokens.length == distribution.length);

    // Update the call and remove the previous allocations
    employee.tokenAllocationCalls++;
    delete employee.tokens;
    delete employee.tokenDistribution;

    for(uint256 i = 0; i < tokens.length; i++){
      bool tokenAllowed = false;
      uint256 distributionTotal = 0;

      // ensure the token is allowed for the employee to use
      for(uint256 ii = 0; ii < employee.allowedTokens.length; ii++){
        if(tokens[i] == employee.allowedTokens[ii]){
          tokenAllowed = true;
          distributionTotal += distribution[i];
          break;
        }
      }

      // If an address for a token is not in the allowed tokens for an employee then we revert()
      if(!tokenAllowed)
          revert();

      // Add new token and distribution
      employee.tokens.push(tokens[i]);
      employee.tokenDistribution.push(distribution[i]);

    }

    // If the token breakup is greater than 100 then we revert to the prevoius state
    // This can be done earlier, but the same number iterations is done either way
    if(distributionTotal != 100)
      revert();

    LogEmployeeAllocationChanged(employeeId, tokens, distribution);
  }

  /**
    * @dev Pays the employee based on their token distribution model
    */
  function payday() public ifNoIssues onlyEmployee {
    Employee storage employee = employees[employeeIdLookup[msg.sender]];

    require(employee.startDate - now % oneMonthInSeconds > employee.paydayCalls);

    employee.paydayCalls++; // This stops reentrancy

    // Calculate the tokens to pay the employee via their distribution model and oracle exchange rate
    for(uint256 i = 0; i < employee.tokens.length; i++){

      address token = employee.tokens[i];
      uint256 tokensToTransfer = (employee.yearlyEURSalary / 12) * exchangeRates[token] * employee.tokenDistribution[i] / 100;

      // Checking if it is ether from this contract
      if(token != address(this)){

        HumanStandardToken hstToken = HumanStandardToken(token);

        // Check that the the necessary funds are in the account
        // Use approve and transfer pattern
        if(hstToken.balanceOf(address(this)) >= tokensToTransfer){
          hstToken.approve(employee.accountAddress, tokensToTransfer);

          // Ensure the transfer works otherwise revert to the last state
          if(!hstToken.transferFrom(msg.sender, employee.accountAddress, tokensToTransfer)){

            // This will happen in a failed approval or failed transfer since a transfer will fail with no approval
            LogEmployeePayFailure(employeeIdLookup[msg.sender], token, tokensToTransfer);
            revert();
          }
        } else {
          LogInsufficientFundsToPayEmployee(employeeIdLookup[msg.sender], token, tokensToTransfer);
          revert();
        }
      } else {
        // Handles sending ether from the current contract
        if(this.balance >= tokensToTransfer){
          msg.sender.transfer(tokensToTransfer);
        } else {
          LogInsufficientFundsToPayEmployee(employeeIdLookup[msg.sender], token, tokensToTransfer);
          revert();
        }
      }
    }

    LogEmployeePaid(employeeIdLookup[msg.sender], employee.yearlyEURSalary / 12, now);
  }

}