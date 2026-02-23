# Supabase 后端转码（微信同款思路）

目标：视频上传后由“后端转码”，生成兼容性更高的 MP4，然后写回 `media_url_transcoded`，客户端优先播放该地址。

## 1) 数据库字段
在 Supabase SQL Editor 执行：

```sql
alter table chat_messages add column if not exists media_url_transcoded text;
```

## 2) Storage 目录约定
转码后文件存放在：
```
chat/transcoded/<message_id>.mp4
```

Bucket 使用 `chat-media`（Public）。

## 3) 转码 Worker（PowerShell）
使用 `docs/transcode_worker.ps1` 作为“后端转码服务”运行（可以放在任意服务器/电脑）。

运行前要求：
- 已安装 `ffmpeg` 并加入 PATH
- 可访问 Supabase URL

运行方式：
```
cd "D:\teacher_hub\docs"
.\transcode_worker.ps1
```

## 4) 客户端播放
客户端已优先使用 `media_url_transcoded`，如果为空才会播放 `media_url`。

## 5) 说明
这套方案等价于“微信类应用”的后端转码流程：
上传原视频 → 后端转码 → 写回转码地址 → 客户端播放转码视频。
