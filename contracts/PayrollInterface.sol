pragma solidity 0.4.19;

// For the sake of simplicity lets assume EUR is a ERC20 token
// Also lets assume we can 100% trust the exchange rate oracle
contract PayrollInterface {

    /* ORACLE ONLY */
    function setExchangeRate(address token, uint256 EURExchangeRate) public; // uses decimals from token

    /* EMPLOYEE ONLY */
    function determineAllocation(address[] tokens, uint256[] distribution) public; // only callable once every 6 months
    function payday() public; // only callable once a month

    /* OWNER ONLY */
    function addEmployee(address accountAddress, address[] allowedTokens, uint256 initialYearlyEURSalary) public;
    function getEmployee(uint256 employeeId) constant public returns (address accountAddress, uint256 yearlyEURSalary, address[] allowedTokens, address[]tokens, uint256[] tokenDistribution); // Return all important info too
    function removeEmployee(uint256 employeeId) public;
    function setEmployeeSalary(uint256 employeeId, uint256 yearlyEURSalary) public;
    function getEmployeeCount() constant public returns (uint256);

    function addManagedToken(address token) public;
    function addFunds() payable public;
    function addTokenFunds(address token, uint256 amount) public;
    function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData) public;

    function calculatePayrollBurnrate() constant public returns (uint256); // Monthly EUR amount spent in salaries
    function calculatePayrollRunway() constant public returns (uint256); // Days until the contract can run out of funds

    function changeOracle(address _oracle) public; // Changes the oracle address
}