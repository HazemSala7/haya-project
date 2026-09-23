<?php

use Illuminate\Foundation\Application;
use Illuminate\Http\Request;

/*
|--------------------------------------------------------------------------
| Front controller — shared-hosting layout
|--------------------------------------------------------------------------
|
| Layout:
|
|   public_html/haya/        ← the static dashboard
|   public_html/haya/api/    ← this file (Laravel's public directory)
|   public_html/haya/_app/   ← the application: .env, storage, config
|
| `_app` belongs ABOVE the document root, not inside it. It is here only
| because this deployment's FTP account is chrooted to public_html and cannot
| write a sibling directory. What keeps .env off the web is `_app/.htaccess`
| (`Require all denied`) — which must be verified returning 403 over HTTPS at
| deploy time, not assumed.
|
| That verification matters more here than on the other systems sharing this
| server: `_app/storage` holds session photographs and video of disabled
| children, and they are served only through AttachmentController, which
| checks the viewer against the child's guardians first.
|
*/

define('LARAVEL_START', microtime(true));

$app_base = __DIR__.'/../_app';

/*
 * Apache already consumed `/haya/api` by serving this directory, so Laravel
 * must register its API routes at the root — otherwise every path would need
 * to be /haya/api/api/students.
 *
 * Set here rather than in .env because routing is configured inside
 * bootstrap/app.php, which runs *before* the .env file is read: an
 * `env('API_PREFIX')` there sees nothing and silently falls back to the
 * default. The mount point is a deployment-specific fact and this is the
 * deployment-specific file, so it belongs here.
 *
 * phpdotenv does not overwrite values that already exist, so the matching
 * line in .env stays consistent rather than fighting this.
 */
$_SERVER['API_PREFIX'] = '';
putenv('API_PREFIX=');

// Determine if the application is in maintenance mode...
if (file_exists($maintenance = $app_base.'/storage/framework/maintenance.php')) {
    require $maintenance;
}

// Register the Composer autoloader...
require $app_base.'/vendor/autoload.php';

// Bootstrap Laravel and handle the request...
/** @var Application $app */
$app = require_once $app_base.'/bootstrap/app.php';

$app->handleRequest(Request::capture());
