'use strict';

const http = require('http');
const isNumber = require('is-number');

const rawPort = process.env.PORT || '3000';
const port = isNumber(rawPort) ? Number(rawPort) : 3000;

function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (requestUrl.pathname === '/healthz') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  sendJson(res, 200, {
    message: 'SRE Quick Hacks demo app is running',
    path: requestUrl.pathname
  });
});

server.listen(port, '0.0.0.0', () => {
  console.log(`Demo server listening on port ${port}`);
});

function shutdown(signal) {
  console.log(`Received ${signal}, shutting down`);

  const forceExit = setTimeout(() => {
    process.exit(1);
  }, 5000);
  forceExit.unref();

  server.close(() => {
    clearTimeout(forceExit);
    process.exit(0);
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
