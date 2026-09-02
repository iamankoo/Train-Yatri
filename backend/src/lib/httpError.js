/// A typed error carrying exactly what's safe to send to a client -
/// an HTTP status, a stable machine-readable `code` (what Flutter
/// switches on to pick a UI state), and a fixed, pre-written
/// `safeMessage` - never a provider's own raw error text, per Block 6
/// Part 9 ("The Flutter app must never expose raw provider errors").
export class HttpError extends Error {
  constructor(status, code, safeMessage) {
    super(safeMessage);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    this.safeMessage = safeMessage;
  }
}

export const Errors = {
  invalidTrainNumber: () =>
    new HttpError(
      400,
      'invalid_train_number',
      'Enter a valid train number.',
    ),
  invalidDate: () =>
    new HttpError(400, 'invalid_date', 'Enter a valid journey date.'),
  notConfigured: () =>
    new HttpError(
      503,
      'provider_not_configured',
      'Live status is temporarily unavailable.',
    ),
  notFound: () =>
    new HttpError(
      404,
      'not_found',
      "Live status isn't available for this train.",
    ),
  rateLimited: () =>
    new HttpError(
      429,
      'rate_limited',
      'Live status is temporarily unavailable. Please try again later.',
    ),
  providerUnavailable: () =>
    new HttpError(
      503,
      'provider_unavailable',
      'Live status is temporarily unavailable.',
    ),
  timeout: () =>
    new HttpError(
      504,
      'timeout',
      'Live status is temporarily unavailable.',
    ),
  upstreamError: () =>
    new HttpError(
      502,
      'upstream_error',
      'Live status is temporarily unavailable.',
    ),
};
