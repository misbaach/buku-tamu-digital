import { fetchGroups } from '$lib/features/guests/query';

export async function load({ params }) {
  return { groups: await fetchGroups(params.id) };
}
