import React, { useCallback } from 'react';
import { TouchableWithoutFeedback, View } from 'react-native';
import { useAuth } from '../contexts/AuthContext';

interface IdleTimeoutHandlerProps {
  children: React.ReactNode;
}

export default function IdleTimeoutHandler({ children }: IdleTimeoutHandlerProps) {
  const { resetIdleTimer, isAuthenticated } = useAuth();

  const handleInteraction = useCallback(() => {
    if (isAuthenticated) {
      resetIdleTimer();
    }
  }, [isAuthenticated, resetIdleTimer]);

  return (
    <TouchableWithoutFeedback
      onPress={handleInteraction}
      onLongPress={handleInteraction}
      onPressIn={handleInteraction}
    >
      <View style={{ flex: 1 }}>
        {children}
      </View>
    </TouchableWithoutFeedback>
  );
}
