import { WorkerEntrypoint } from 'cloudflare:workers';
import type { BackendEnv } from './auth';
import { handleAdminRequest } from './admin-router';

/** The public fetch handler does not route to this entrypoint. */
export class AdminAPI extends WorkerEntrypoint<BackendEnv> {
  fetch(request:Request){return handleAdminRequest(request,this.env);}
}
