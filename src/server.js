const express = require('express');
const { body, validationResult } = require('express-validator');
const ordersRouter = require('./routes/orders');
const healthRouter = require('./routes/health');

const app = express();
const PORT = process.env.PORT || 8080;
const SERVICE_ENV = process.env.SERVICE_ENV || 'local';

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${SERVICE_ENV}] ${req.method} ${req.path}`);
  next();
});

// Routes
app.use('/health', healthRouter);
app.use('/orders', ordersRouter);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'order-api',
    environment: SERVICE_ENV,
    version: '1.0.0',
    status: 'running'
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: {
      message: err.message || 'Internal server error',
      environment: SERVICE_ENV
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: {
      message: 'Not found',
      path: req.path
    }
  });
});

// Start server only if this file is run directly (not imported by tests)
if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Order API server running on port ${PORT} in ${SERVICE_ENV} environment`);
  });
}

module.exports = app;

