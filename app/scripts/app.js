'use strict';

angular
  .module('walletClientApp', [
    'ngCookies',
    'ngResource',
    'ngSanitize',
    'ngRoute'
  ])
  .config(function ($routeProvider) {
    $routeProvider
      .when('/', {
        templateUrl: 'views/main.html',
        controller: 'MainCtrl'
      })
      .when('/rpc', {
        templateUrl: 'views/rpc.html',
        controller: 'RpcCtrl'
      })
      .otherwise({
        redirectTo: '/'
      });
  });
