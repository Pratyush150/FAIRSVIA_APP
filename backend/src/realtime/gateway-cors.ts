/**
 * CORS policy for the Socket.IO handshake, mirroring the HTTP policy in
 * main.ts: reflect any origin in dev; in production only the CORS_ORIGINS
 * allow-list (or no browser origin at all when it's empty). Native mobile
 * clients send no Origin header and are unaffected either way.
 *
 * Read from process.env because @WebSocketGateway() options are evaluated at
 * class-definition time, before Nest's ConfigService exists.
 */
export function gatewayCors(env: NodeJS.ProcessEnv = process.env): {
  origin: boolean | string[];
  credentials: boolean;
} {
  const isProd = env.NODE_ENV === 'production';
  const origins = (env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);
  return {
    origin: isProd ? (origins.length > 0 ? origins : false) : true,
    credentials: true,
  };
}
