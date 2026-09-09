import { defineBoot } from '#q-app/wrappers';

import { initFrameworkStyle } from '../utils/frameworkStyle';

export default defineBoot(() => {
  initFrameworkStyle();
});
