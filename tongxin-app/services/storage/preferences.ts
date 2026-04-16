import AsyncStorage from '@react-native-async-storage/async-storage';

const LANGUAGE_KEY = 'tongxin_language';
const SPOT_FILL_RECEIPT_MUTED_KEY = 'tongxin_spot_fill_receipt_muted';

export async function saveLanguagePreference(language: 'zh' | 'en') {
  await AsyncStorage.setItem(LANGUAGE_KEY, language);
}

export async function loadLanguagePreference(): Promise<'zh' | 'en' | null> {
  try {
    const value = await AsyncStorage.getItem(LANGUAGE_KEY);
    if (value === 'zh' || value === 'en') {
      return value;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * 用户是否勾选了「现货市价成交回执弹窗 · 下次不再提示」。
 * 读失败默认返回 false（=显示弹窗），避免因存储异常导致用户漏看关键成交信息。
 */
export async function getSpotFillReceiptMuted(): Promise<boolean> {
  try {
    const value = await AsyncStorage.getItem(SPOT_FILL_RECEIPT_MUTED_KEY);
    return value === 'true';
  } catch {
    return false;
  }
}

export async function setSpotFillReceiptMuted(muted: boolean): Promise<void> {
  try {
    if (muted) {
      await AsyncStorage.setItem(SPOT_FILL_RECEIPT_MUTED_KEY, 'true');
    } else {
      await AsyncStorage.removeItem(SPOT_FILL_RECEIPT_MUTED_KEY);
    }
  } catch {
    // 静默失败：静默不影响交易主流程
  }
}
