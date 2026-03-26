-- 清理：删除「已接受」但双方已不在 friends 表的好友申请记录
-- 原因：旧版删好友只删了 friends，没删 friend_requests，导致再添加时仍提示「已是好友」
-- 若之前整段 DELETE 一直 Running 不结束，先点「停止」，再按下面步骤做。

-- ========== 步骤 1（可选）：加索引，加速后面的删除 ==========
-- 若表已有主键或对应索引可跳过；没有的话执行下面两行会快很多。
-- CREATE INDEX IF NOT EXISTS idx_friend_requests_status ON public.friend_requests (status);
-- CREATE INDEX IF NOT EXISTS idx_friends_user_friend ON public.friends (user_id, friend_id);

-- ========== 步骤 2：分批删除（每次最多 500 条，多跑几次直到影响行数为 0）==========
-- 在 Supabase SQL Editor 里只执行下面这一段；跑完看 "Rows affected"。
-- 若 > 0，再点 Run 再执行一次，直到 Rows affected = 0。

DELETE FROM public.friend_requests
WHERE id IN (
  SELECT fr.id
  FROM public.friend_requests fr
  WHERE fr.status = 'accepted'
    AND NOT EXISTS (
      SELECT 1 FROM public.friends f
      WHERE (f.user_id = fr.requester_id AND f.friend_id = fr.receiver_id)
         OR (f.user_id = fr.receiver_id AND f.friend_id = fr.requester_id)
    )
  LIMIT 500
);
