import { defineBoot } from '#q-app/wrappers';

import {
  applyAppLogoFavicon,
  resolveAppLogoCandidate,
} from 'src/components/appLogoConfig';

export default defineBoot(() => {
  void resolveAppLogoCandidate().then((candidate) => {
    applyAppLogoFavicon(candidate);
  });
});
