<?php

/*
|--------------------------------------------------------------------------
| Cross-Origin Resource Sharing
|--------------------------------------------------------------------------
|
| The dashboard is a static export served from the same host as the API, so in
| production this file does almost nothing. It exists for development, where
| `next dev` runs on localhost and talks to the deployed API.
|
| The origins are named rather than left as Laravel's default `['*']`. A
| wildcard is not a hole on its own — every call here carries a bearer token
| that a stranger's page does not have — but this API hands out session
| photographs of disabled children, and "no page on any origin may even attempt
| a read" is a cheaper thing to guarantee than to argue about.
|
| `supports_credentials` stays false: authentication is a bearer token in
| localStorage, never a cookie, so there is nothing for a browser to attach
| automatically and therefore nothing CSRF can ride on.
|
*/

return [

    'paths' => ['api/*', '/*'],

    'allowed_methods' => ['*'],

    /*
     * The dev ports are listed one by one rather than wildcarded.
     *
     * 3010 is this project's own. 3000 and 3001 belong to another app on this
     * machine ("Attendify"), which also registers a service worker — and a
     * service worker is scoped to the ORIGIN, not the project, so it hijacks
     * every app served on that port afterwards. That is what made this
     * dashboard render blank there. A port nobody else uses is the whole fix;
     * 3000 and 3001 stay listed only so an accidental fallback still works.
     */
    'allowed_origins' => [
        'https://neurex.ps',
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        'http://localhost:3001',
        'http://127.0.0.1:3001',
        'http://localhost:3010',
        'http://127.0.0.1:3010',
        'http://localhost:3020',
        'http://127.0.0.1:3020',
    ],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 3600,

    'supports_credentials' => false,

];
