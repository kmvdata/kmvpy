export const APP_LOGO_TEXT = "Sisyphus";

export interface AppLogoCandidate {
  fileName: string;
  mimeType: string;
  sizes: string;
  src: string;
}

const APP_LOGO_BASE_FILE_NAME = "app-logo";
const APP_LOGO_BASE_URL = import.meta.env.BASE_URL;

const buildAppLogoCandidate = (
  extension: string,
  mimeType: string,
  sizes = "512x512",
): AppLogoCandidate => {
  const fileName = `${APP_LOGO_BASE_FILE_NAME}.${extension}`;

  return {
    fileName,
    mimeType,
    sizes,
    src: `${APP_LOGO_BASE_URL}${fileName}`,
  };
};

export const APP_LOGO_CANDIDATES = [
  buildAppLogoCandidate("svg", "image/svg+xml", "any"),
  buildAppLogoCandidate("png", "image/png"),
  buildAppLogoCandidate("jpg", "image/jpeg"),
  buildAppLogoCandidate("jpeg", "image/jpeg"),
  buildAppLogoCandidate("webp", "image/webp"),
] as const;

export const APP_LOGO_MIN_RASTER_SIZE = 512;
export const APP_LOGO_FILE_NAME = APP_LOGO_CANDIDATES[0].fileName;
export const APP_LOGO_SRC = APP_LOGO_CANDIDATES[0].src;

let resolvedAppLogoCandidatePromise: Promise<AppLogoCandidate> | undefined;

export const resolveAppLogoCandidate = (): Promise<AppLogoCandidate> => {
  if (typeof window === "undefined") {
    return Promise.resolve(APP_LOGO_CANDIDATES[0]);
  }

  resolvedAppLogoCandidatePromise ??= resolveFirstAvailableCandidate();
  return resolvedAppLogoCandidatePromise;
};

export const applyAppLogoFavicon = (candidate: AppLogoCandidate): void => {
  if (typeof document === "undefined") {
    return;
  }

  upsertFaviconLink("icon", candidate);
  upsertFaviconLink("shortcut icon", candidate);
};

async function resolveFirstAvailableCandidate(): Promise<AppLogoCandidate> {
  for (const candidate of APP_LOGO_CANDIDATES) {
    if (await canLoadImage(candidate.src)) {
      return candidate;
    }
  }

  return APP_LOGO_CANDIDATES[0];
}

function canLoadImage(src: string): Promise<boolean> {
  return new Promise((resolve) => {
    const image = new Image();

    image.onload = () => resolve(true);
    image.onerror = () => resolve(false);
    image.src = src;
  });
}

function upsertFaviconLink(
  rel: "icon" | "shortcut icon",
  candidate: AppLogoCandidate,
) {
  const selector = `link[data-app-logo-favicon="${rel}"]`;
  const existingLink = document.querySelector<HTMLLinkElement>(selector);
  const fallbackLink = document.querySelector<HTMLLinkElement>(
    `link[rel="${rel}"]`,
  );
  const link = existingLink ?? fallbackLink ?? document.createElement("link");

  link.dataset.appLogoFavicon = rel;
  link.rel = rel;
  link.type = candidate.mimeType;
  link.setAttribute("sizes", candidate.sizes);
  link.href = candidate.src;

  if (!link.parentElement) {
    document.head.appendChild(link);
  }
}
