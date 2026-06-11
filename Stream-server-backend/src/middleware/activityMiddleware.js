export const activityTracker = (powerManager) => {
  return (req, res, next) => {
    powerManager.recordUserActivity();
    next();
  };
};
