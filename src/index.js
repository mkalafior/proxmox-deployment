#!/usr/bin/env bun

console.log("🚀 Hello World from Bun on Proxmox!");
console.log("=".repeat(40));

const server = Bun.serve({
    port: process.env.PORT || 3000,
    hostname: process.env.HOST || "0.0.0.0",

    fetch(request) {
        const url = new URL(request.url);

        // Health check endpoint
        if (url.pathname === "/health") {
            return new Response(JSON.stringify({
                status: "healthy",
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                version: "1.0.0"
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        // Root endpoint
        if (url.pathname === "/") {
            return new Response(`
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - Bun on Proxmox</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 2rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 2rem;
            border-radius: 10px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        h1 {
            text-align: center;
            margin-bottom: 2rem;
            font-size: 2.5rem;
        }
        .info {
            background: rgba(255, 255, 255, 0.1);
            padding: 1rem;
            border-radius: 5px;
            margin: 1rem 0;
        }
        .status {
            color: #4ade80;
            font-weight: bold;
        }
        .endpoint {
            background: rgba(0, 0, 0, 0.2);
            padding: 0.5rem;
            border-radius: 3px;
            font-family: monospace;
            margin: 0.5rem 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Hello World from Bun!</h1>
        
        <div class="info">
            <h3>🖥️ Server Information</h3>
            <p><strong>Runtime:</strong> Bun ${Bun.version}</p>
            <p><strong>Platform:</strong> Proxmox VM</p>
            <p><strong>Status:</strong> <span class="status">Running</span></p>
            <p><strong>Time:</strong> ${new Date().toLocaleString()}</p>
            <p><strong>Uptime:</strong> ${Math.floor(process.uptime())} seconds</p>
        </div>
        
        <div class="info">
            <h3>🔗 Available Endpoints</h3>
            <div class="endpoint">GET /health - Health check endpoint</div>
            <div class="endpoint">GET / - This page</div>
        </div>
        
        <div class="info">
            <h3>📦 Deployment Info</h3>
            <p>This application was deployed using Ansible to a Proxmox Virtual Environment.</p>
            <p>The deployment includes automated VM creation, OS configuration, and application setup.</p>
        </div>
    </div>
</body>
</html>
      `, {
                headers: { "Content-Type": "text/html" }
            });
        }

        // API endpoint with some data
        if (url.pathname === "/api/info") {
            return new Response(JSON.stringify({
                app: "hello-world-bun-app",
                version: "1.0.0",
                runtime: "Bun",
                bunVersion: Bun.version,
                platform: "Proxmox VM",
                timestamp: new Date().toISOString(),
                uptime: process.uptime(),
                environment: process.env.NODE_ENV || "development",
                endpoints: [
                    { path: "/", method: "GET", description: "Homepage" },
                    { path: "/health", method: "GET", description: "Health check" },
                    { path: "/api/info", method: "GET", description: "Application info" }
                ]
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        // 404 for other routes
        return new Response("Not Found", { status: 404 });
    },

    error(error) {
        console.error("Server error:", error);
        return new Response("Internal Server Error", { status: 500 });
    }
});

console.log(`✅ Server running on http://${server.hostname}:${server.port}`);
console.log(`📊 Health check: http://${server.hostname}:${server.port}/health`);
console.log(`🔧 API info: http://${server.hostname}:${server.port}/api/info`);
console.log(`💻 Runtime: Bun ${Bun.version}`);
