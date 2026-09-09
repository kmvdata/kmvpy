<template>
  <q-item
    :id="entryId"
    ref="entry"
    clickable
    role="menuitem"
    aria-haspopup="menu"
    :aria-expanded="open"
    :aria-controls="open ? menuId : undefined"
    class="account-style-menu__preference"
    @click="toggle"
    @keydown.right.stop.prevent="expand"
  >
    <q-item-section avatar><q-icon :name="icon" /></q-item-section>
    <q-item-section>
      <q-item-label>{{ label }}</q-item-label>
      <q-item-label caption>{{ currentLabel }}</q-item-label>
    </q-item-section>
    <q-item-section side><q-icon :name="chevron" /></q-item-section>
    <q-menu
      ref="submenu"
      :id="menuId"
      :model-value="open"
      no-parent-event
      no-refocus
      no-focus
      :transition-duration="0"
      :anchor="anchor"
      :self="self"
      :offset="[4, 4]"
      :aria-labelledby="entryId"
      class="account-style-menu account-style-menu__submenu"
      @update:model-value="emit('update:open', $event)"
      @show="focusSelected"
      @before-show="queueSelectedFocus"
      @escape-key="returnToEntry"
      @keydown.left.stop.prevent="returnToEntry"
      @keydown.up.stop.prevent="moveOption($event, -1)"
      @keydown.down.stop.prevent="moveOption($event, 1)"
    >
      <q-resize-observer :debounce="0" @resize="submenu?.updatePosition()" />
      <q-list role="presentation">
        <q-item
          v-for="option in options"
          :key="option.value"
          clickable
          role="menuitemradio"
          :aria-checked="option.value === value"
          @click="select(option.value)"
        >
          <q-item-section>{{ option.label }}</q-item-section>
          <q-item-section side>
            <q-icon
              name="check"
              :class="{ invisible: option.value !== value }"
            />
          </q-item-section>
        </q-item>
      </q-list>
    </q-menu>
  </q-item>
  <div
    v-if="reserveSpace && placement === 'below'"
    aria-hidden="true"
    class="account-style-menu__submenu-space"
    :style="{ '--account-submenu-rows': options.length }"
  />
</template>

<script setup lang="ts">
import { computed, nextTick, ref, useId, watch } from "vue";
import { useQuasar, type QItem, type QMenu } from "quasar";

const props = defineProps<{
  label: string;
  icon: string;
  value: string;
  options: ReadonlyArray<{ label: string; value: string }>;
  open: boolean;
  reserveSpace: boolean;
}>();
const emit = defineEmits<{
  "update:open": [value: boolean];
  select: [value: string];
  return: [];
}>();
const $q = useQuasar();
const entry = ref<QItem>();
const submenu = ref<QMenu>();
const id = useId();
const entryId = `account-preference-${id}`;
const menuId = `${entryId}-menu`;
const placement = ref<"left" | "right" | "below">("left");
const currentLabel = computed(
  () => props.options.find((item) => item.value === props.value)?.label,
);
const anchor = computed(() =>
  placement.value === "below"
    ? "bottom left"
    : placement.value === "left"
      ? "top left"
      : "top right",
);
const self = computed(() =>
  placement.value === "left" ? "top right" : "top left",
);
const chevron = computed(() =>
  placement.value === "below" ? "expand_more" : `chevron_${placement.value}`,
);

function updatePlacement() {
  const element = entry.value?.$el as HTMLElement | undefined;
  if (!element) return;
  const rect = element.getBoundingClientRect();
  const width = Number.parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue(
      "--account-submenu-width",
    ),
  );
  placement.value =
    rect.left >= width + 12
      ? "left"
      : $q.screen.width - rect.right >= width + 12
        ? "right"
        : "below";
}
function expand() {
  updatePlacement();
  emit("update:open", true);
}
function toggle() {
  if (props.open) returnToEntry();
  else expand();
}
function focusSelected() {
  if (!props.open) return;
  const menu = document.getElementById(menuId);
  // Do not steal focus if a fast keyboard user already reached another option.
  if (menu?.contains(document.activeElement)) return;
  menu?.querySelector<HTMLElement>('[aria-checked="true"]')?.focus();
}
function queueSelectedFocus() {
  void nextTick(focusSelected);
}
function returnToEntry() {
  emit("update:open", false);
  emit("return");
  void nextTick(() =>
    (entry.value?.$el as HTMLElement | undefined)?.focus({
      preventScroll: true,
    }),
  );
}
function select(value: string) {
  emit("select", value);
  returnToEntry();
}
function moveOption(event: KeyboardEvent, step: number) {
  const items = Array.from(
    document
      .getElementById(menuId)
      ?.querySelectorAll<HTMLElement>('[role="menuitemradio"]') ?? [],
  );
  const index = items.findIndex((item) => item.contains(event.target as Node));
  items[(index + step + items.length) % items.length]?.focus();
}
watch(
  () => [$q.screen.width, props.value],
  () => {
    if (props.open) updatePlacement();
  },
);
</script>
