'use strict';

describe('Controller: RpcCtrl', function () {

  // load the controller's module
  beforeEach(module('walletClientApp'));

  var RpcCtrl,
    scope;

  // Initialize the controller and a mock scope
  beforeEach(inject(function ($controller, $rootScope) {
    scope = $rootScope.$new();
    RpcCtrl = $controller('RpcCtrl', {
      $scope: scope
    });
  }));

  it('should attach a list of awesomeThings to the scope', function () {
    expect(scope.awesomeThings.length).toBe(3);
  });
});
