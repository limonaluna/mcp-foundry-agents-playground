// Simplified authentication middleware for API key only
import { Request, Response, NextFunction } from 'express';

export interface UserContext {
  userId: string;
  source: 'api-key' | 'anonymous';
}

/**
 * API Key authentication middleware
 * Checks for API key in X-API-Key header or Authorization header (Bearer token)
 */
export function apiKeyAuth(req: Request, res: Response, next: NextFunction) {
  const apiKey = req.headers['x-api-key'] as string || 
                  (req.headers['authorization'] as string)?.replace('Bearer ', '');
  
  const expectedApiKey = process.env.API_KEY;
  
  if (!expectedApiKey) {
    console.warn('⚠️ WARNING: API_KEY environment variable not set - authentication disabled');
    (req as any).userContext = { userId: 'anonymous', source: 'anonymous' };
    return next();
  }
  
  if (!apiKey) {
    console.log('❌ Authentication failed: No API key provided');
    return res.status(401).json({ 
      error: 'Unauthorized', 
      message: 'API key required. Provide via X-API-Key header or Authorization: Bearer <key>'
    });
  }
  
  if (apiKey !== expectedApiKey) {
    console.log('❌ Authentication failed: Invalid API key');
    return res.status(401).json({ 
      error: 'Unauthorized', 
      message: 'Invalid API key'
    });
  }
  
  // Valid API key
  (req as any).userContext = {
    userId: 'authenticated-user',
    source: 'api-key'
  };
  
  next();
}

/**
 * Get user context from request
 */
export function getUserContext(req: Request): UserContext {
  return (req as any).userContext || { userId: 'anonymous', source: 'anonymous' };
}

/**
 * Simple rate limiting middleware (in-memory, per IP)
 */
const requestCounts = new Map<string, { count: number; resetTime: number }>();

export function rateLimiter(options: { 
  windowMs?: number; 
  maxRequests?: number;
} = {}) {
  const windowMs = options.windowMs || 60000; // 1 minute default
  const maxRequests = options.maxRequests || 100;
  
  return (req: Request, res: Response, next: NextFunction) => {
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const now = Date.now();
    
    let record = requestCounts.get(ip);
    
    if (!record || now > record.resetTime) {
      record = { count: 0, resetTime: now + windowMs };
      requestCounts.set(ip, record);
    }
    
    record.count++;
    
    if (record.count > maxRequests) {
      return res.status(429).json({
        error: 'Too Many Requests',
        message: `Rate limit exceeded. Try again in ${Math.ceil((record.resetTime - now) / 1000)} seconds.`
      });
    }
    
    next();
  };
}

/**
 * Cleanup old rate limit records periodically
 */
setInterval(() => {
  const now = Date.now();
  for (const [ip, record] of requestCounts.entries()) {
    if (now > record.resetTime) {
      requestCounts.delete(ip);
    }
  }
}, 60000); // Clean up every minute
