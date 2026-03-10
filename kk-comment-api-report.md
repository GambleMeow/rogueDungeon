# KK comment-api 帖子评论列表接口 抓取报告

**目标**：找出 comment-api 的「帖子评论列表」接口

---

## 1) 执行步骤与阻塞点

| 步骤 | 结果 | 说明 |
|-----|------|------|
| 1) 打开 fab/180750 | ✓ | 页面正常加载 |
| 2) 进入「社区攻略」tab | ✓ | 可点击，加载 page_query_topics |
| 3) 点击攻略帖进入详情 | ✗ | **阻塞**：无法稳定点击进入帖子详情弹层/页面 |
| 4) 评论区滚动并抓包 | - | 因步骤3未成功，未捕获到帖子级评论接口请求 |

**阻塞原因**：社区攻略内容可能由远程模块（h5modules）或 iframe 渲染，帖子列表的 DOM 选择器与预期不符，自动化点击未能触发详情弹层。

---

## 2) 已捕获的 comment-api 接口（与评论/楼中楼/分页相关）

### 2.1 话题列表（帖子列表）— 可直接访问

| URL | 方法 | 状态 | 请求参数 | 说明 |
|-----|------|------|----------|------|
| `https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=180750&orderType=1&start=0&limit=10` | GET | 200 | mapId, orderType, start, limit | 分页获取话题列表 |

### 2.2 帖子评论列表 — 需 token

| URL | 方法 | 状态 | 请求参数 | 说明 |
|-----|------|------|----------|------|
| `https://comment-api.kkdzpt.com/api/v1/topic/comments?mapId=180750&topicId={topicId}&start=0&limit=10` | GET | **403** | mapId, topicId, start, limit | 返回 `{"status":40301,"message":"token is required"}` |
| `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/topic/comments?...` | GET | **403** | 同上 | 同上 |
| `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/topic/replies?...` | GET | **403** | 同上 | 同上 |

### 2.3 已排除的路径（404）

| URL | 状态 |
|-----|------|
| `/api/v1/comment/list` | 404 |
| `/api/v1/comment/page` | 404 |
| `/api/v1/comment/reply_list` | 404 |
| `/api/v1/reply/list` | 404 |

---

## 3) 可直接访问的接口示例

### 3.1 话题列表（帖子列表）

```
GET https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=180750&orderType=1&start=0&limit=10
```

**请求参数**：
- `mapId`：地图ID（180750）
- `orderType`：排序（1=默认）
- `start`：分页偏移
- `limit`：每页条数

**响应示例**：
```json
{
  "status": 200,
  "data": [
    {
      "topicId": "65151b52cdddb63ebc890efc",
      "title": "肉鸽地牢详细攻略（一）流派选择＆伤害计算",
      "content": "<p>攻略肯定不是全能的...</p>",
      "commentCount": 192,
      "className": "攻略",
      "releaseTime": "2023-09-28 14:21:06",
      "userViewRes": { "playerName": "LuckyApple", ... }
    }
  ]
}
```

### 3.2 帖子评论列表（需登录 token）

```
GET https://comment-api.kkdzpt.com/api/v1/topic/comments?mapId=180750&topicId=65151b52cdddb63ebc890efc&start=0&limit=10
```

**请求参数**：
- `mapId`：地图ID
- `topicId`：帖子ID（来自 page_query_topics 的 topicId）
- `start`：分页偏移
- `limit`：每页条数

**当前响应**（未带 token）：
```json
{
  "status": 40301,
  "message": "token is required"
}
```

---

## 4) 替代方案

1. **手动抓包**：在浏览器中登录 KK 平台，打开帖子详情并滚动评论区，用 DevTools Network 筛选 `comment-api`，可确认评论接口的完整 URL、参数和响应结构。
2. **使用 comment/search**：`/api/v1/comment/search` 为地图级「精选评论」，参数含 `replyLimit`，可返回带楼中楼的评论，但为地图维度，非按 topicId 的帖子评论。
3. **话题内容**：`page_query_topics` 和 `top_data` 已包含帖子 `content`，若只需正文无需楼中楼，可直接使用上述接口。

---

## 5) 结论

| 接口 | 用途 | 可直接访问 |
|------|------|------------|
| `topic/page_query_topics` | 帖子列表 | ✓ |
| `topic/top_data` | 置顶帖子 | ✓ |
| `topic/comments` | 帖子评论列表 | ✗（需 token） |
| `topic/replies`（gateway） | 帖子回复 | ✗（需 token） |

**帖子评论列表接口**：`/api/v1/topic/comments`，参数为 `mapId`、`topicId`、`start`、`limit`，需携带平台 token 方可访问。
