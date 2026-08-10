enum PermissionStep {
  location,
  notifications,
  done,
}

extension PermissionStepX on PermissionStep {
  PermissionStep next() {
    switch (this) {
      case PermissionStep.location:
        return PermissionStep.notifications;
      case PermissionStep.notifications:
        return PermissionStep.done;
      case PermissionStep.done:
        return PermissionStep.done;
    }
  }
}
