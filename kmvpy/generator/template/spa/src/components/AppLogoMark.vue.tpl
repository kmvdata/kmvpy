<template>
  <img
    class="app-logo-mark"
    :src="currentLogoSrc"
    alt=""
    decoding="async"
    draggable="false"
    @error="handleLogoLoadError"
  />
</template>

<script setup lang="ts">
import { computed, ref } from "vue";

import { APP_LOGO_CANDIDATES } from "src/components/appLogoConfig";

const currentLogoCandidateIndex = ref(0);

const currentLogoSrc = computed(
  () =>
    (APP_LOGO_CANDIDATES[currentLogoCandidateIndex.value] ?? APP_LOGO_CANDIDATES[0])
      .src,
);

function handleLogoLoadError() {
  if (currentLogoCandidateIndex.value < APP_LOGO_CANDIDATES.length - 1) {
    currentLogoCandidateIndex.value += 1;
  }
}
</script>

<style scoped>
.app-logo-mark {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  object-position: center center;
}
</style>
