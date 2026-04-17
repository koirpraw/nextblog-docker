import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */

  // Skip type checking and linting during build (for faster builds on low-resource instances)
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
  },

  webpack: (config) => {
    // Fix for @uiw/react-md-editor
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      path: false,
    };
    return config;
  },
};

export default nextConfig;
