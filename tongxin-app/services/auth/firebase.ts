/**
 * Firebase initialization (JS SDK for Expo)
 *
 * Uses the Firebase JS SDK which works with Expo without native modules.
 * For production, consider @react-native-firebase with a custom dev client.
 */
import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import {
  getAuth,
  initializeAuth,
  // @ts-ignore - expo adapter
  getReactNativePersistence,
  type Auth,
} from 'firebase/auth';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Platform } from 'react-native';
import { Config } from '../config';

let app: FirebaseApp;
let auth: Auth;

export function getFirebaseApp(): FirebaseApp {
  if (app) return app;
  if (getApps().length > 0) {
    app = getApp();
  } else {
    app = initializeApp(Config.FIREBASE);
  }
  return app;
}

export function getFirebaseAuth(): Auth {
  if (auth) return auth;
  const firebaseApp = getFirebaseApp();

  if (Platform.OS === 'web') {
    auth = getAuth(firebaseApp);
  } else {
    // Use AsyncStorage for auth persistence on native
    try {
      auth = initializeAuth(firebaseApp, {
        persistence: getReactNativePersistence(AsyncStorage),
      });
    } catch {
      // Already initialized
      auth = getAuth(firebaseApp);
    }
  }
  return auth;
}
