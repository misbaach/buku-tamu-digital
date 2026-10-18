<script lang="ts">
  import type { Snippet } from 'svelte';

  // Pola ARIA tabs: panah kiri/kanan, Home/End; hanya tab aktif yang ada di urutan Tab.
  interface Props {
    tabs: { id: string; label: string }[];
    active: string;
    label: string;
    panel: Snippet<[string]>;
  }

  let { tabs, active = $bindable(), label, panel }: Props = $props();
  const uid = $props.id();

  function onkeydown(event: KeyboardEvent, index: number) {
    const last = tabs.length - 1;
    const next =
      event.key === 'ArrowRight'
        ? (index + 1) % tabs.length
        : event.key === 'ArrowLeft'
          ? (index - 1 + tabs.length) % tabs.length
          : event.key === 'Home'
            ? 0
            : event.key === 'End'
              ? last
              : null;
    if (next === null) return;
    event.preventDefault();
    const tab = tabs[next];
    if (!tab) return;
    active = tab.id;
    document.getElementById(`${uid}-tab-${tab.id}`)?.focus();
  }
</script>

<div role="tablist" aria-label={label} class="flex gap-1 border-b border-line">
  {#each tabs as tab, i (tab.id)}
    <button
      type="button"
      role="tab"
      id="{uid}-tab-{tab.id}"
      aria-selected={active === tab.id}
      aria-controls="{uid}-panel"
      tabindex={active === tab.id ? 0 : -1}
      class={[
        '-mb-px cursor-pointer border-b-2 px-3 py-2 text-sm font-medium',
        active === tab.id ? 'border-ink text-ink' : 'border-transparent text-ink-muted hover:text-ink',
      ]}
      onclick={() => (active = tab.id)}
      onkeydown={(e) => onkeydown(e, i)}
    >
      {tab.label}
    </button>
  {/each}
</div>
<div role="tabpanel" id="{uid}-panel" aria-labelledby="{uid}-tab-{active}" class="pt-4">
  {@render panel(active)}
</div>
