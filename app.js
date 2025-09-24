const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

// Health check endpoint (important for ECS!)
app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: process.env.APP_VERSION || '1.0.0'
    });
});

// Main route
app.get('/', (req, res) => {
    res.json({
        message: 'Hello from ECS Fargate!',
        container_id: process.env.HOSTNAME,
        environment: process.env.NODE_ENV || 'development',
        version: process.env.APP_VERSION || '1.0.0'
    });
});

// API route
app.get('/api/info', (req, res) => {
    res.json({
        app: 'My ECS Application',
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        cpu_arch: process.arch,
        node_version: process.version
    });
});

app.listen(port, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${port}`);
    console.log(`📊 Health check: http://localhost:${port}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('👋 Received SIGTERM, shutting down gracefully');
    process.exit(0);
});
