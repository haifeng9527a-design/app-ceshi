# 为 call_invitations 启用 Supabase Realtime（含 UPDATE 事件）

要让主叫能通过 Realtime **实时**收到被叫的「接听 / 拒绝 / 取消」，需要做两件事：

1. **把表加入 Realtime 的 Publication**（这样 INSERT/UPDATE/DELETE 才会被推送）
2. **确认主叫能读到这条记录**（RLS 的 SELECT 策略要允许主叫查自己发起的邀请）

下面用「界面操作」和「SQL」两种方式说明，任选其一即可。

---

## 一、概念简要说明

- **Publication（发布）**：Supabase 的 Realtime 通过 Postgres 的「逻辑复制」把表的变化推给客户端。表必须被加进名为 `supabase_realtime` 的 publication，才会推送变更。
- **默认会推送的事件**：把表加入 publication 后，**INSERT、UPDATE、DELETE** 都会推送（不需要单独再开「UPDATE 事件」）。你只需要把表加进 publication。
- **RLS 与 Realtime**：Realtime 推送时会对**订阅者**做 RLS 检查。若主叫用户对某行没有 SELECT 权限，就收不到该行的 UPDATE。所以主叫必须能 SELECT「自己发起的邀请」那一行。

---

## 二、方法 A：在 Supabase Dashboard 里操作（推荐）

### 步骤 1：打开 Realtime 的 Publication 设置

1. 登录 [Supabase Dashboard](https://app.supabase.com/)
2. 选中你的项目
3. 左侧菜单点 **Database**
4. 在 Database 子菜单里点 **Replication**（或 **Publications**，不同版本可能写「Replication」或「Publications」）

### 步骤 2：找到并编辑 `supabase_realtime`

1. 在列表里找到 **supabase_realtime** 这条 publication
2. 点进去（或点右侧的编辑/齿轮图标），进入「这个 publication 包含哪些表」的配置

### 步骤 3：把 `call_invitations` 加进 publication

1. 在「Tables in publication」或「Add tables」区域，找到 **public.call_invitations**
2. 勾选 **call_invitations**（或点「Add table」再选 `call_invitations`）
3. 保存

保存后，该表的 **INSERT、UPDATE、DELETE** 都会通过 Realtime 推送，无需再单独勾选「只发 UPDATE」。

### 步骤 4：（可选）确认 Realtime 已开启

- 若项目里有 **Database → Realtime** 或 **Project Settings → Realtime**，确认 Realtime 是 **Enabled**
- 一般新建项目默认已开，若从未关过可跳过

---

## 三、方法 B：用 SQL 添加表到 Publication

不想用界面的话，在 **SQL Editor** 里执行下面语句即可。

```sql
-- 把 call_invitations 加入 Realtime 的 publication
-- 加入后，该表的 INSERT / UPDATE / DELETE 都会推送给订阅的客户端
ALTER PUBLICATION supabase_realtime ADD TABLE public.call_invitations;
```

若提示「表已在 publication 中」，说明已经加过了，不用再执行。

**如何执行：**

1. Dashboard 左侧 **SQL Editor**
2. 新建查询，粘贴上面一句
3. 点 **Run**（或 Ctrl+Enter）

---

## 四、让主叫能收到 UPDATE（RLS SELECT 策略）

当前 RLS 里，**SELECT 只允许「被叫」**（`to_user_id = 当前用户`）。主叫（`from_user_id = 当前用户`）不能 SELECT 自己发起的邀请，Realtime 就不会把该行的 UPDATE 推给主叫。

要让主叫也能实时收到状态更新，需要允许主叫查自己发起的邀请，加一条 SELECT 策略即可：

```sql
-- 主叫：可查询自己发起的邀请（用于 Realtime 收接听/拒绝/取消）
CREATE POLICY "call_invitations_select_as_caller"
  ON public.call_invitations FOR SELECT
  USING (auth.jwt() ->> 'sub' = from_user_id);
```

**执行方式**：同上，在 **SQL Editor** 里新建查询，粘贴后 Run。

（若之前已经为「主叫可读」建过同名或等价策略，会报「policy already exists」，可忽略或先 `DROP POLICY ...` 再建。）

---

## 五、如何确认已经生效

### 1. 确认表在 publication 里（SQL）

在 SQL Editor 执行：

```sql
SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';
```

结果里应有一行 `schemaname = 'public'` 且 `tablename = 'call_invitations'`。

### 2. 确认会发 UPDATE（理解即可）

- 把表加入 `supabase_realtime` 后，Postgres 会复制该表的 **INSERT、UPDATE、DELETE**
- Supabase Realtime 服务会把这些变更推给订阅了该表（或该行）的客户端
- 不需要在 Dashboard 里再勾选「只发 UPDATE」；默认就是全事件

### 3. 实际测试

- 主叫发起通话，被叫点「接听」或「拒绝」
- 主叫端应在 **约 1–2 秒内**（或更快）出现「对方已接听」/「对方已拒绝」并更新界面或关闭页面
- 若仍不更新，说明可能仍只走轮询（每 2 秒一次）；检查：
  - 上面 publication 和 RLS 是否都做了
  - 主叫是否已登录（`auth.jwt() ->> 'sub'` 是否为发起邀请的 `from_user_id`）

---

## 六、小结：你要做的清单

| 步骤 | 做什么 | 方式 |
|------|--------|------|
| 1 | 把 `call_invitations` 加入 `supabase_realtime` | Dashboard → Database → Replication → 勾选表；或执行 `ALTER PUBLICATION supabase_realtime ADD TABLE public.call_invitations;` |
| 2 | 让主叫能读自己发起的邀请 | SQL Editor 执行上面的 `CREATE POLICY "call_invitations_select_as_caller" ...` |
| 3 | 确认 | `pg_publication_tables` 中有 `call_invitations`，再实机测主叫是否实时收到接听/拒绝 |

完成后，主叫会通过 Realtime 实时收到状态；即便 Realtime 暂时不可用，应用内的**轮询兜底**（每 2 秒查一次状态）仍会保证主叫最终能收到并自动关闭或更新界面。
