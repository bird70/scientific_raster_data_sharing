/**
 * Hook for managing time animation
 */

import { useState, useEffect, useRef } from 'react';

interface UseTimeAnimationOptions {
  timeSteps: string[];
  currentStep: number;
  onStepChange: (step: number | ((prev: number) => number)) => void;
  speed?: number; // milliseconds per step
  loop?: boolean;
}

export function useTimeAnimation({
  timeSteps,
  onStepChange,
  speed = 1000,
  loop = true,
}: UseTimeAnimationOptions) {
  const [isPlaying, setIsPlaying] = useState(false);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Clean up interval on unmount
  useEffect(() => {
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []);

  // Handle animation
  useEffect(() => {
    if (!isPlaying) {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    intervalRef.current = setInterval(() => {
      onStepChange((prevStep: number) => {
        const nextStep = prevStep + 1;
        
        // Check if we've reached the end
        if (nextStep >= timeSteps.length) {
          if (loop) {
            return 0; // Loop back to start
          } else {
            setIsPlaying(false); // Stop at end
            return prevStep;
          }
        }
        
        return nextStep;
      });
    }, speed);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [isPlaying, speed, loop, timeSteps.length, onStepChange]);

  const togglePlayPause = () => {
    setIsPlaying((prev) => !prev);
  };

  const stop = () => {
    setIsPlaying(false);
    onStepChange(0);
  };

  return {
    isPlaying,
    togglePlayPause,
    stop,
  };
}
