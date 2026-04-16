import { useEffect, useMemo, useState } from 'react';
import {
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import { Colors, Shadows } from '../../theme/colors';
import {
  dismissDialog,
  subscribeDialog,
  type DialogRequest,
  type DialogVariant,
} from '../../services/utils/dialog';
import AppIcon, { type AppIconName } from './AppIcon';

function iconNameForVariant(variant: DialogVariant): AppIconName {
  switch (variant) {
    case 'success':
      return 'check';
    case 'warning':
      return 'shield';
    case 'danger':
      return 'close';
    default:
      return 'sparkles';
  }
}

function accentForVariant(variant: DialogVariant) {
  switch (variant) {
    case 'success':
      return Colors.up;
    case 'warning':
      return Colors.warning;
    case 'danger':
      return Colors.down;
    default:
      return Colors.primary;
  }
}

export default function DialogHost() {
  const [dialog, setDialog] = useState<DialogRequest | null>(null);
  const [inputValue, setInputValue] = useState('');
  const [inputError, setInputError] = useState<string | null>(null);

  useEffect(() => subscribeDialog(setDialog), []);

  useEffect(() => {
    if (!dialog) {
      setInputValue('');
      setInputError(null);
      return;
    }
    setInputValue(dialog.input?.defaultValue ?? '');
    setInputError(null);
  }, [dialog]);

  const accent = useMemo(
    () => accentForVariant(dialog?.variant ?? 'info'),
    [dialog?.variant],
  );

  const handleAction = (actionKey: string, requiresInput?: boolean) => {
    if (!dialog) return;

    if (requiresInput && dialog.input?.validator) {
      const nextError = dialog.input.validator(inputValue);
      if (nextError) {
        setInputError(nextError);
        return;
      }
    }

    dismissDialog(actionKey, requiresInput ? inputValue : undefined);
  };

  return (
    <Modal
      visible={!!dialog}
      transparent
      animationType="fade"
      onRequestClose={() => {
        if (dialog?.dismissible === false) return;
        dismissDialog(dialog?.cancelActionKey ?? '__dismiss__');
      }}
    >
      <KeyboardAvoidingView
        style={styles.overlay}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <Pressable
          style={styles.backdrop}
          onPress={() => {
            if (dialog?.dismissible === false) return;
            dismissDialog(dialog?.cancelActionKey ?? '__dismiss__');
          }}
        />

        <View style={styles.centerWrap}>
          <View style={styles.dialog}>
            <View style={[styles.iconWrap, { borderColor: `${accent}33`, backgroundColor: `${accent}18` }]}>
              <AppIcon name={iconNameForVariant(dialog?.variant ?? 'info')} size={22} color={accent} />
            </View>

            {!!dialog?.title && <Text style={styles.title}>{dialog.title}</Text>}
            {!!dialog?.message && <Text style={styles.message}>{dialog.message}</Text>}

            {dialog?.input && (
              <View style={styles.inputWrap}>
                <TextInput
                  value={inputValue}
                  onChangeText={(text) => {
                    setInputValue(text);
                    if (inputError) setInputError(null);
                  }}
                  placeholder={dialog.input.placeholder}
                  placeholderTextColor={Colors.textMuted}
                  secureTextEntry={dialog.input.secureTextEntry}
                  keyboardType={dialog.input.keyboardType}
                  autoCapitalize="none"
                  autoCorrect={false}
                  style={styles.input}
                />
                {!!inputError && <Text style={styles.inputError}>{inputError}</Text>}
              </View>
            )}

            <View style={styles.actions}>
              {dialog?.actions.map((action) => {
                const primary = action.tone === 'primary';
                const danger = action.tone === 'danger';
                return (
                  <TouchableOpacity
                    key={action.key}
                    activeOpacity={0.88}
                    style={[
                      styles.actionBtn,
                      primary && styles.actionBtnPrimary,
                      danger && styles.actionBtnDanger,
                    ]}
                    onPress={() => handleAction(action.key, !!dialog.input && action.submitsInput)}
                  >
                    <Text
                      style={[
                        styles.actionBtnText,
                        primary && styles.actionBtnTextPrimary,
                        danger && styles.actionBtnTextDanger,
                      ]}
                    >
                      {action.label}
                    </Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: Colors.overlayBg,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
  },
  centerWrap: {
    width: '100%',
    paddingHorizontal: 20,
    alignItems: 'center',
  },
  dialog: {
    width: '100%',
    maxWidth: 460,
    borderRadius: 28,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    backgroundColor: Colors.surface,
    paddingHorizontal: 24,
    paddingVertical: 24,
    alignItems: 'stretch',
    ...Shadows.card,
  },
  iconWrap: {
    width: 50,
    height: 50,
    borderRadius: 16,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  title: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    marginBottom: 10,
  },
  message: {
    color: Colors.textSecondary,
    fontSize: 15,
    lineHeight: 23,
    marginBottom: 18,
  },
  inputWrap: {
    marginBottom: 18,
  },
  input: {
    minHeight: 52,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    backgroundColor: Colors.inputBg,
    color: Colors.textActive,
    fontSize: 15,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  inputError: {
    color: Colors.down,
    marginTop: 8,
    fontSize: 13,
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    justifyContent: 'flex-end',
    flexWrap: 'wrap',
  },
  actionBtn: {
    minWidth: 112,
    height: 46,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 18,
  },
  actionBtnPrimary: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primary,
  },
  actionBtnDanger: {
    borderColor: Colors.downDim,
    backgroundColor: Colors.downDim,
  },
  actionBtnText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  actionBtnTextPrimary: {
    color: Colors.textOnPrimary,
  },
  actionBtnTextDanger: {
    color: Colors.down,
  },
});
