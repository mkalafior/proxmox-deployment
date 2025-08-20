// Generated service: service02
const server = Bun.serve({
    port: process.env.PORT || 3002,
    hostname: process.env.HOST || "0.0.0.0",
    fetch(req) {
        const url = new URL(req.url);

        if (url.pathname === "/health") {
            return new Response(JSON.stringify({
                status: "healthy",
                service: "service02",
                timestamp: new Date().toISOString()
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        if (url.pathname === "/") {
            return new Response(JSON.stringify({
                message: "Hello from service02 (background-worker)!",
                service: "service02",
                hostname: "background-worker",
                port: server.port
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`🚀 service02 (background-worker) running on http://${server.hostname}:${server.port}`);
