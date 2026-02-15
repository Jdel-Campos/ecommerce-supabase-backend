export {};

declare global {
  // Minimal typing for Deno in edge functions so TypeScript tooling
  // recognizes the global without depending on Deno-specific libs.
  const Deno: {
    serve: (handler: (req: Request) => Response | Promise<Response>) => void;
  };
}


