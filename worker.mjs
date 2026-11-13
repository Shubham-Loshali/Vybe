import policy from './check.json' with { type: 'json' };

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);
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
