import { Alert, Platform } from 'react-native';
import i18n from '../../i18n';

export type DialogVariant = 'info' | 'success' | 'warning' | 'danger';
export type DialogActionTone = 'neutral' | 'primary' | 'danger';

export type DialogAction = {
  key: string;
  label: string;
  tone?: DialogActionTone;
  submitsInput?: boolean;
};

export type DialogRequest = {
  id: number;
  title?: string;
  message: string;
  variant: DialogVariant;
  actions: DialogAction[];
  dismissible?: boolean;
  cancelActionKey?: string;
  input?: {
    placeholder?: string;
    defaultValue?: string;
    secureTextEntry?: boolean;
    keyboardType?: 'default' | 'email-address' | 'numeric' | 'url';
    validator?: (value: string) => string | undefined;
  };
};

type DialogListener = (dialog: DialogRequest | null) => void;
type DialogResolver = (actionKey?: string, inputValue?: string) => void;

let nextDialogId = 1;
let activeDialog: DialogRequest | null = null;
let activeResolver: DialogResolver | null = null;
const queue: Array<{ request: DialogRequest; resolve: DialogResolver }> = [];
const listeners = new Set<DialogListener>();
let alertBridgeInstalled = false;
let originalAlert: typeof Alert.alert | null = null;

function emitDialog() {
  listeners.forEach((listener) => listener(activeDialog));
}

function hasDialogHost() {
  return listeners.size > 0;
}

function flushNextDialog() {
  const next = queue.shift();
  if (!next) {
    activeDialog = null;
    activeResolver = null;
    emitDialog();
    return;
  }

  activeDialog = next.request;
  activeResolver = next.resolve;
  emitDialog();
}

function enqueueDialog(request: Omit<DialogRequest, 'id'>, resolve: DialogResolver) {
  const withId: DialogRequest = { ...request, id: nextDialogId++ };
  if (!activeDialog) {
    activeDialog = withId;
    activeResolver = resolve;
    emitDialog();
    return;
  }
  queue.push({ request: withId, resolve });
}

export function subscribeDialog(listener: DialogListener) {
  listeners.add(listener);
  listener(activeDialog);
  return () => {
    listeners.delete(listener);
  };
}

export function dismissDialog(actionKey?: string, inputValue?: string) {
  const resolver = activeResolver;
  activeDialog = null;
  activeResolver = null;
  emitDialog();
  resolver?.(actionKey, inputValue);
  flushNextDialog();
}

export function showDialog(request: Omit<DialogRequest, 'id'>): Promise<{ actionKey?: string; inputValue?: string }> {
  return new Promise((resolve) => {
    if (!hasDialogHost()) {
      resolve({ actionKey: request.actions[0]?.key });
      console.warn('[dialog] DialogHost unavailable, resolved without rendering dialog:', request);
      return;
    }

    enqueueDialog(request, (actionKey, inputValue) => resolve({ actionKey, inputValue }));
  });
}

export function showAlert(message: string, title?: string, variant: DialogVariant = 'info'): void {
  void showDialog({
    title,
    message,
    variant,
    dismissible: true,
    cancelActionKey: 'confirm',
    actions: [{ key: 'confirm', label: i18n.t('common.confirm'), tone: 'primary' }],
  });
}

export async function showConfirm(message: string, title?: string): Promise<boolean> {
  const result = await showDialog({
    title,
    message,
    variant: 'warning',
    dismissible: true,
    cancelActionKey: 'cancel',
    actions: [
      { key: 'cancel', label: i18n.t('common.cancel'), tone: 'neutral' },
      { key: 'confirm', label: i18n.t('common.confirm'), tone: 'primary' },
    ],
  });

  return result.actionKey === 'confirm';
}

export async function showPrompt(options: {
  title?: string;
  message: string;
  placeholder?: string;
  defaultValue?: string;
  secureTextEntry?: boolean;
  keyboardType?: 'default' | 'email-address' | 'numeric' | 'url';
  confirmLabel?: string;
  cancelLabel?: string;
  validator?: (value: string) => string | undefined;
}): Promise<string | null> {
  const result = await showDialog({
    title: options.title,
    message: options.message,
    variant: 'info',
    dismissible: true,
    cancelActionKey: 'cancel',
    input: {
      placeholder: options.placeholder,
      defaultValue: options.defaultValue,
      secureTextEntry: options.secureTextEntry,
      keyboardType: options.keyboardType,
      validator: options.validator,
    },
    actions: [
      { key: 'cancel', label: options.cancelLabel ?? i18n.t('common.cancel'), tone: 'neutral' },
      { key: 'confirm', label: options.confirmLabel ?? i18n.t('common.confirm'), tone: 'primary', submitsInput: true },
    ],
  });

  if (result.actionKey !== 'confirm') return null;
  return result.inputValue ?? '';
}

type AlertBridgeButton = {
  text?: string;
  style?: 'default' | 'cancel' | 'destructive';
  onPress?: () => void;
};

export function installDialogAlertBridge() {
  if (alertBridgeInstalled || Platform.OS !== 'web') return;

  originalAlert = Alert.alert.bind(Alert);
  (Alert as unknown as { alert: typeof Alert.alert }).alert = ((
    title?: string,
    message?: string,
    buttons?: AlertBridgeButton[],
    options?: { cancelable?: boolean }
  ) => {
    const nativeButtons = Array.isArray(buttons) && buttons.length > 0
      ? buttons
      : [{ text: i18n.t('common.confirm') }];

    if (!hasDialogHost()) {
      console.warn('[dialog] Alert bridge fell back to native alert before host mounted:', {
        title,
        message,
      });
      originalAlert?.(title ?? '', message, buttons, options);
      return;
    }

    const normalizedActions: DialogAction[] = nativeButtons.map((button, index) => {
      const tone: DialogActionTone = button.style === 'destructive'
        ? 'danger'
        : button.style === 'cancel'
          ? 'neutral'
          : 'primary';

      return {
        key: `alert_action_${index}`,
        label: button.text || i18n.t('common.confirm'),
        tone,
      };
    });

    const variant: DialogVariant = nativeButtons.some((button) => button.style === 'destructive')
      ? 'danger'
      : nativeButtons.length > 1
        ? 'warning'
        : 'info';

    const cancelAction = nativeButtons.findIndex((button) => button.style === 'cancel');

    void showDialog({
      title,
      message: message ?? '',
      variant,
      dismissible: options?.cancelable !== false,
      cancelActionKey: cancelAction >= 0 ? `alert_action_${cancelAction}` : undefined,
      actions: normalizedActions,
    }).then(({ actionKey }) => {
      const matchedIndex = normalizedActions.findIndex((action) => action.key === actionKey);
      if (matchedIndex >= 0) {
        nativeButtons[matchedIndex]?.onPress?.();
      }
    });
  }) as typeof Alert.alert;

  alertBridgeInstalled = true;
}
