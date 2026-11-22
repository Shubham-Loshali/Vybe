import policy from './check.json' with { type: 'json' };

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);
    const download = pathname.match(/^\/download\/(v\d+\.\d+\.\d+)\/companion\/Vybe\.apk$/);
    if (download) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return new Response('Method Not Allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
      }
      // Keep the companion's signed bytes, but give Android the familiar filename.
      const source = `https://github.com/Shubham-Loshali/Vybe/releases/download/${download[1]}/Vybe-companion.apk`;
      const headers = new Headers();
      for (const name of ['Range', 'If-Range']) {
        const value = request.headers.get(name);
        if (value) headers.set(name, value);
      }
      try {
        const upstream = await fetch(source, { method: request.method, headers, redirect: 'follow' });
        if (!upstream.ok) {
          await upstream.body?.cancel();
          return new Response('APK download unavailable. Please retry.', {
            status: upstream.status === 404 ? 404 : 502,
            headers: { 'Cache-Control': 'no-store' },
          });
        }
        const outputHeaders = new Headers({
          'Content-Type': 'application/vnd.android.package-archive',
          'Content-Disposition': 'attachment; filename="Vybe.apk"',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Allow-Origin': '*',
        });
        for (const name of ['Content-Length', 'Content-Range', 'Accept-Ranges', 'ETag', 'Last-Modified']) {
          const value = upstream.headers.get(name);
          if (value) outputHeaders.set(name, value);
        }
        return new Response(request.method === 'HEAD' ? null : upstream.body, {
          status: upstream.status,
          headers: outputHeaders,
        });
      } catch {
        return new Response('APK download unavailable. Please retry.', {
          status: 502, headers: { 'Cache-Control': 'no-store' },
        });
      }
    }
    if (pathname !== '/check' && pathname !== '/') {
      return new Response('Not Found', { status: 404 });
    }
    return Response.json(policy, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
      },
    });
  },
};
