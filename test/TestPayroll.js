// Specifically request an abstraction for Payroll
var Payroll = artifacts.require("Payroll");

contract('Payroll', function() {

  let payroll;

  //create new smart contract instance before each test method
  beforeEach(async function() {
      payroll = await Payroll.new();
  });

  it("Should have zero employees", async function() {
    assert.equal(await payroll.getEmployeeCount(), 0, "There was not zero employees");
  });

  it("Should have one employee", async function() {
    await payroll.addEmployee("0xca35b7d915458ef540ade6068dfe2f44e8fa733c", ["0xca35b7d915458ef540ade6068dfe2f44e8fa733c"], 105000);
    assert.equal(await payroll.getEmployeeCount(), 1, "There was not one employee");
  });

  it("Employee should have the same values it was created with", async function() {
    await payroll.addEmployee("0xca35b7d915458ef540ade6068dfe2f44e8fa733c", ["0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb"], 105000);
    let employee = await payroll.getEmployee.call(1);
    assert.equal(employee[0], "0xca35b7d915458ef540ade6068dfe2f44e8fa733c", "Employee account address doesn't match");
    assert.equal(employee[1], 105000, "Employee salary doesn't match");
    assert.equal(employee[2][0], "0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb", "Employee salary doesn't match");
  });

  it("Employee should be added and then removed", async function() {
    await payroll.addEmployee("0xca35b7d915458ef540ade6068dfe2f44e8fa733c", ["0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb"], 105000);
    assert.equal(await payroll.getEmployeeCount(), 1, "There was not one employee");
    await payroll.removeEmployee(1);
    assert.equal(await payroll.getEmployeeCount(), 0, "There was not zero employees");
  });

  it("Calculate the expected monthly burnrate", async function() {
    await payroll.addEmployee("0xfb6916095ca1df60bb79Ce92ce3ea74c37c5d359", [], 105000);
    await payroll.addEmployee("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb", [], 85000);
    await payroll.addEmployee("0xca35b7d915458ef540ade6068dfe2f44e8fa733c", [], 133000);
    let monthlyExpectedBurn = Math.floor( (105000 + 85000 + 133000) / 12 );
    let burnRate = await payroll.calculatePayrollBurnrate();
    assert.equal(burnRate, monthlyExpectedBurn, "Monthly payroll did match expect value of: " + monthlyExpectedBurn);
  });

  it("Calculate the expected monthly burnrate after employee salary adjustment", async function() {
    await payroll.addEmployee("0xfb6916095ca1df60bb79Ce92ce3ea74c37c5d359", [], 105000);
    await payroll.addEmployee("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb", [], 85000);
    await payroll.addEmployee("0xca35b7d915458ef540ade6068dfe2f44e8fa733c", [], 133000);
    await payroll.setEmployeeSalary(1, 95000);
    let employee1 = await payroll.getEmployee.call(1);
    await payroll.setEmployeeSalary(3, 155000);
    let employee3 = await payroll.getEmployee.call(3);
    assert.equal(employee1[1], 95000, "Employee1 salary doesn't match");
    assert.equal(employee3[1], 155000, "Employee3 salary doesn't match");
    let monthlyExpectedBurn = Math.floor( (95000 + 85000 + 155000) / 12 );
    let burnRate = await payroll.calculatePayrollBurnrate();
    assert.equal(burnRate, monthlyExpectedBurn, "Monthly payroll did match expect value of: " + monthlyExpectedBurn);
  });

});