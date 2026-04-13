import React, { useRef, useCallback, useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Platform,
  ScrollView,
} from 'react-native';
import { Colors } from '../../theme/colors';
import apiClient from '../../services/api/client';

interface RichTextEditorProps {
  initialContent?: string;
  onContentChange?: (html: string) => void;
  placeholder?: string;
  editable?: boolean;
  minHeight?: number;
}

// ── Toolbar Button ──
function ToolbarBtn({
  label,
  onPress,
  active,
}: {
  label: string;
  onPress: () => void;
  active?: boolean;
}) {
  return (
    <TouchableOpacity
      style={[styles.toolbarBtn, active && styles.toolbarBtnActive]}
      onPress={onPress}
    >
      <Text style={[styles.toolbarBtnText, active && styles.toolbarBtnTextActive]}>
        {label}
      </Text>
    </TouchableOpacity>
  );
}

export default function RichTextEditor({
  initialContent = '',
  onContentChange,
  placeholder = '开始撰写策略...',
  editable = true,
  minHeight = 400,
}: RichTextEditorProps) {
  const editorRef = useRef<any>(null);
  const fileInputRef = useRef<any>(null);
  const [isFocused, setIsFocused] = useState(false);
  const [isEmpty, setIsEmpty] = useState(!initialContent);
  const [uploading, setUploading] = useState(false);
  const composingRef = useRef(false);
  const mountedRef = useRef(false);

  const handleImageUpload = async () => {
    if (Platform.OS === 'web' && fileInputRef.current) {
      fileInputRef.current.click();
    }
  };

  const onFileSelected = async (e: any) => {
    const file = e.target?.files?.[0];
    if (!file) return;

    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const { data } = await apiClient.post('/api/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      const imageUrl = apiClient.defaults.baseURL + data.url;
      document.execCommand('insertImage', false, imageUrl);
      // Trigger content change
      const html = editorRef.current?.innerHTML || '';
      onContentChange?.(html);
    } catch (err) {
      console.error('Upload failed:', err);
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  // Web implementation using contentEditable
  if (Platform.OS === 'web') {
    return (
      <View style={styles.container}>
        {editable && (
          <View style={styles.toolbar}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.toolbarContent}>
              <ToolbarBtn label="B" onPress={() => document.execCommand('bold')} />
              <ToolbarBtn label="I" onPress={() => document.execCommand('italic')} />
              <ToolbarBtn label="U" onPress={() => document.execCommand('underline')} />
              <ToolbarBtn label="S" onPress={() => document.execCommand('strikeThrough')} />
              <View style={styles.toolbarDivider} />
              <ToolbarBtn label="H1" onPress={() => document.execCommand('formatBlock', false, 'h1')} />
              <ToolbarBtn label="H2" onPress={() => document.execCommand('formatBlock', false, 'h2')} />
              <ToolbarBtn label="H3" onPress={() => document.execCommand('formatBlock', false, 'h3')} />
              <ToolbarBtn label="P" onPress={() => document.execCommand('formatBlock', false, 'p')} />
              <View style={styles.toolbarDivider} />
              <ToolbarBtn label="UL" onPress={() => document.execCommand('insertUnorderedList')} />
              <ToolbarBtn label="OL" onPress={() => document.execCommand('insertOrderedList')} />
              <ToolbarBtn label="引用" onPress={() => document.execCommand('formatBlock', false, 'blockquote')} />
              <View style={styles.toolbarDivider} />
              <ToolbarBtn label="代码" onPress={() => document.execCommand('formatBlock', false, 'pre')} />
              <ToolbarBtn
                label="链接"
                onPress={() => {
                  const url = prompt('输入链接地址:');
                  if (url) document.execCommand('createLink', false, url);
                }}
              />
              <ToolbarBtn
                label={uploading ? '...' : '图片'}
                onPress={handleImageUpload}
              />
              <View style={styles.toolbarDivider} />
              <ToolbarBtn label="撤销" onPress={() => document.execCommand('undo')} />
              <ToolbarBtn label="重做" onPress={() => document.execCommand('redo')} />
            </ScrollView>
          </View>
        )}

        {/* Hidden file input for image upload */}
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          style={{ display: 'none' }}
          onChange={onFileSelected}
        />

        <View style={[styles.editorWrapper, isFocused && styles.editorFocused]}>
          {isEmpty && !isFocused && (
            <Text style={styles.placeholder}>{placeholder}</Text>
          )}
          <div
            ref={(node) => {
              editorRef.current = node;
              if (node && !mountedRef.current) {
                mountedRef.current = true;
                node.innerHTML = initialContent;

                // IME composition handlers
                node.addEventListener('compositionstart', () => {
                  composingRef.current = true;
                });
                node.addEventListener('compositionend', () => {
                  composingRef.current = false;
                  const html = node.innerHTML || '';
                  setIsEmpty(!html || html === '<br>');
                  onContentChange?.(html);
                });
              }
            }}
            contentEditable={editable}
            suppressContentEditableWarning
            dir="ltr"
            onFocus={() => setIsFocused(true)}
            onBlur={() => {
              setIsFocused(false);
              const html = editorRef.current?.innerHTML || '';
              setIsEmpty(!html || html === '<br>');
            }}
            onInput={() => {
              if (composingRef.current) return; // Don't update during IME composition
              const html = editorRef.current?.innerHTML || '';
              setIsEmpty(!html || html === '<br>');
              onContentChange?.(html);
            }}
            style={{
              minHeight,
              outline: 'none',
              color: Colors.textActive,
              fontSize: 15,
              lineHeight: 1.8,
              padding: 16,
              fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
              direction: 'ltr' as any,
              textAlign: 'left' as any,
            }}
            className="rich-editor"
          />
          <style
            dangerouslySetInnerHTML={{
              __html: `
                .rich-editor h1 { font-size: 28px; font-weight: 800; color: ${Colors.textActive}; margin: 24px 0 12px; }
                .rich-editor h2 { font-size: 22px; font-weight: 700; color: ${Colors.textActive}; margin: 20px 0 10px; }
                .rich-editor h3 { font-size: 18px; font-weight: 600; color: ${Colors.textActive}; margin: 16px 0 8px; }
                .rich-editor p { margin: 8px 0; color: ${Colors.textSecondary}; }
                .rich-editor ul, .rich-editor ol { padding-left: 24px; margin: 8px 0; color: ${Colors.textSecondary}; }
                .rich-editor li { margin: 4px 0; }
                .rich-editor blockquote {
                  border-left: 3px solid ${Colors.primary};
                  padding: 8px 16px;
                  margin: 12px 0;
                  background: ${Colors.surface};
                  border-radius: 0 8px 8px 0;
                  color: ${Colors.textMuted};
                  font-style: italic;
                }
                .rich-editor pre {
                  background: ${Colors.surface};
                  padding: 12px 16px;
                  border-radius: 8px;
                  font-family: 'SF Mono', 'Fira Code', monospace;
                  font-size: 13px;
                  overflow-x: auto;
                  color: ${Colors.textActive};
                  margin: 12px 0;
                }
                .rich-editor code {
                  background: ${Colors.surface};
                  padding: 2px 6px;
                  border-radius: 4px;
                  font-family: 'SF Mono', 'Fira Code', monospace;
                  font-size: 13px;
                  color: ${Colors.primary};
                }
                .rich-editor a { color: ${Colors.primary}; text-decoration: underline; }
                .rich-editor img {
                  max-width: 100%;
                  border-radius: 12px;
                  margin: 12px 0;
                }
                .rich-editor strong { font-weight: 700; color: ${Colors.textActive}; }
                .rich-editor em { font-style: italic; }
                .rich-editor s { text-decoration: line-through; color: ${Colors.textMuted}; }
              `,
            }}
          />
        </View>
      </View>
    );
  }

  // Native fallback - basic TextInput (tentap-editor can be added later for native)
  return (
    <View style={styles.container}>
      <View style={[styles.editorWrapper, { minHeight }]}>
        <Text style={styles.placeholder}>富文本编辑器仅在 Web 端可用</Text>
      </View>
    </View>
  );
}

// ── Read-only HTML renderer ──
export function HtmlContent({ html, style }: { html: string; style?: any }) {
  if (Platform.OS === 'web') {
    return (
      <View style={style}>
        <div
          className="rich-editor"
          dangerouslySetInnerHTML={{ __html: html }}
          style={{
            color: Colors.textSecondary,
            fontSize: 15,
            lineHeight: 1.8,
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
          }}
        />
        <style
          dangerouslySetInnerHTML={{
            __html: `
              .rich-editor h1 { font-size: 28px; font-weight: 800; color: ${Colors.textActive}; margin: 24px 0 12px; }
              .rich-editor h2 { font-size: 22px; font-weight: 700; color: ${Colors.textActive}; margin: 20px 0 10px; }
              .rich-editor h3 { font-size: 18px; font-weight: 600; color: ${Colors.textActive}; margin: 16px 0 8px; }
              .rich-editor p { margin: 8px 0; color: ${Colors.textSecondary}; }
              .rich-editor ul, .rich-editor ol { padding-left: 24px; margin: 8px 0; color: ${Colors.textSecondary}; }
              .rich-editor li { margin: 4px 0; }
              .rich-editor blockquote {
                border-left: 3px solid ${Colors.primary};
                padding: 8px 16px;
                margin: 12px 0;
                background: ${Colors.surface};
                border-radius: 0 8px 8px 0;
                color: ${Colors.textMuted};
                font-style: italic;
              }
              .rich-editor pre {
                background: ${Colors.surface};
                padding: 12px 16px;
                border-radius: 8px;
                font-family: 'SF Mono', 'Fira Code', monospace;
                font-size: 13px;
                overflow-x: auto;
                color: ${Colors.textActive};
                margin: 12px 0;
              }
              .rich-editor code {
                background: ${Colors.surface};
                padding: 2px 6px;
                border-radius: 4px;
                font-family: 'SF Mono', 'Fira Code', monospace;
                font-size: 13px;
                color: ${Colors.primary};
              }
              .rich-editor a { color: ${Colors.primary}; text-decoration: underline; }
              .rich-editor img { max-width: 100%; border-radius: 12px; margin: 12px 0; }
              .rich-editor strong { font-weight: 700; color: ${Colors.textActive}; }
              .rich-editor em { font-style: italic; }
              .rich-editor s { text-decoration: line-through; color: ${Colors.textMuted}; }
            `,
          }}
        />
      </View>
    );
  }

  return (
    <View style={style}>
      <Text style={{ color: Colors.textMuted }}>HTML内容仅在Web端渲染</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  toolbar: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  toolbarContent: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 6,
    gap: 2,
  },
  toolbarBtn: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 6,
    minWidth: 32,
    alignItems: 'center',
  },
  toolbarBtnActive: {
    backgroundColor: Colors.primaryDim,
  },
  toolbarBtnText: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
  },
  toolbarBtnTextActive: {
    color: Colors.primary,
  },
  toolbarDivider: {
    width: 1,
    height: 20,
    backgroundColor: Colors.border,
    marginHorizontal: 4,
  },
  editorWrapper: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    overflow: 'hidden',
    position: 'relative',
  },
  editorFocused: {
    borderColor: Colors.primary,
  },
  placeholder: {
    position: 'absolute',
    top: 16,
    left: 16,
    color: Colors.textMuted,
    fontSize: 15,
    zIndex: 0,
    pointerEvents: 'none',
  },
});
