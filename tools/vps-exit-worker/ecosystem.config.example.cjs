/**
 * Copy to ecosystem.config.cjs on the VPS, set EXIT_NODE_PSK, adjust PORT if needed.
 * Start: pm2 start ecosystem.config.cjs
 * (Plain "pm2 start" only looks for ecosystem.config.js by default.)
 */
module.exports = {
  apps: [
    {
      name: "shade-exit",
      script: "server.js",
      node_args: "--max-http-header-size=65536",
      env: {
        PORT: "18081",
        EXIT_NODE_PSK: "CHANGE_ME_USE_openssl_rand_hex_24",
      },
    },
  ],
};
