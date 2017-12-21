# ReadMe

## Compile and test
* Pull the repository, run ```truffle develop``` then ```test```

### Added Functions
```
function addTokenFunds(address token, uint256 amount) public;
```
* For adding tokens, it uses approveAndCall for the tokens that are being transferred

```
function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData) public;
```
* Supports the approveAndCall method of token transfers above.
```
function changeOracle(address _oracle) public;
```
* Added so that the oracle can be changed by the owner
```
function addManagedToken(address token) public;
```
* Allows the owner to keep track of tokens managed by the contract

## Notes
* EURToken should have be the contract of the EURToken hardcoded (currently a placeholder) and is the default payment method
* Ether is not added a base payment although it could probably be assumed.
* I did not get to finish all the test cases that I would have liked.

## Improvements that were outside the scope of the project
* For the escapehatch() function, the funds could be transferred to another contract that would then hold the funds until the this contract is re-enabled.
* Add a function back to re-enable contract (and start the transfer back if in another contract)
* Add a function to remove a managedToken (which would involve adjusting allocations for all employees)