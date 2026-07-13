import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { MetricsService } from './metrics.service';

/** Records duration + status of every HTTP request into Prometheus metrics. */
@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  constructor(private readonly metrics: MetricsService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();

    const http = context.switchToHttp();
    const req = http.getRequest();
    const start = Date.now();
    // req.route.path is the templated path (e.g. /trips/:id) — low cardinality.
    const route =
      req.route?.path ?? (req.url ?? 'unknown').split('?')[0] ?? 'unknown';

    const record = (status: number) =>
      this.metrics.observe(req.method, route, status, Date.now() - start);

    return next.handle().pipe(
      tap({
        next: () => record(http.getResponse().statusCode ?? 200),
        error: (err) =>
          record(err?.status ?? http.getResponse().statusCode ?? 500),
      }),
    );
  }
}
