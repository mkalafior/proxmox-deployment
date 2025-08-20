// Generated service: service01
const server = Bun.serve({
    port: process.env.PORT || 3001,
    hostname: process.env.HOST || "0.0.0.0",
    fetch(req) {
        const url = new URL(req.url);

        if (url.pathname === "/health") {
            return new Response(JSON.stringify({
                status: "healthy",
                service: "service01",
                timestamp: new Date().toISOString()
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        if (url.pathname === "/") {
            return new Response(JSON.stringify({
                message: "Hello from service01!",
                service: "service01",
                port: server.port
            }), {
                headers: { "Content-Type": "application/json" }
            });
        }

        return new Response("Not Found", { status: 404 });
    },
});

console.log(`🚀 service01 running on http://${server.hostname}:${server.port}`);
