var Payroll = artifacts.require("./Payroll.sol");

module.exports = function(deployer) {
  deployer.deploy(Payroll, { gas: 5000000 });
};
