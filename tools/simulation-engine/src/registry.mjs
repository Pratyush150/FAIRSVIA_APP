// In-process coordination between rider and driver actors. Solves the
// "coupled driver↔rider bookkeeping" gap: a driver that gets assigned a tripId
// can look up the rider's start OTP here instead of the old scripts' fragile
// socket-map juggling (which silently dropped matches to unknown drivers).

const trips = new Map(); // tripId -> { startOtp, riderId }

export const TripRegistry = {
  register(tripId, { startOtp, riderId }) {
    trips.set(tripId, { startOtp, riderId });
  },
  otp(tripId) {
    return trips.get(tripId)?.startOtp ?? null;
  },
  done(tripId) {
    trips.delete(tripId);
  },
  size() {
    return trips.size;
  },
};
