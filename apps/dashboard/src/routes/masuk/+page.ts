import { redirect } from '@sveltejs/kit';
import { currentSession, isAdminSession, safeNextPath } from '$lib/auth';

export async function load({ url }) {
  const session = await currentSession();
  if (isAdminSession(session)) redirect(307, safeNextPath(url.searchParams.get('ke')));
  return { reason: url.searchParams.get('alasan') };
}
