'use strict';

angular.module('walletClientApp')
  .controller('RpcCtrl', function ($scope, $http) {

    $scope.id = '00001';
    $scope.method = 'getinfo';
    $scope.params = '[]';

    $scope.submit = function() {

      $scope.request = {
        "id": $scope.id,
        "method": $scope.method,
        "params": JSON.parse($scope.params)
      };

      $http.post('http://127.0.0.1:5000/bitcoind', $scope.request)
        .success( function(data) {
          // $scope.response = data;
          $scope.response = JSON.stringify(data, null, 4);
        })
        .error( function(data) {
          $scope.response = JSON.stringify(data, null, 4);
        });

    };

  });
