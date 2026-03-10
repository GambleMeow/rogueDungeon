# KK对战平台 肉鸽地牢(180750) API 抓取报告

**目标页面**: https://www.kkdzpt.com/fab/180750

---

## 1) API 清单（URL / 方法 / 状态码）

| API URL | 方法 | 状态码 | Content-Type | 说明 |
|---------|------|--------|--------------|------|
| `https://map-api.kkdzpt.com/api/v2/map/detail?mapId=180750` | GET | 200 | application/json | **地图详情**（核心） |
| `https://comment-api.kkdzpt.com/api/v1/topic/count?mapId=180750` | GET | 200 | application/json | 评论/话题总数 |
| `https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=180750&orderType=1&start=0&limit=10` | GET | 200 | application/json | 社区话题列表（攻略/灌水/bug等） |
| `https://comment-api.kkdzpt.com/api/v1/topic/top_data?mapId=180750` | GET | 200 | application/json | 置顶话题（攻略、协议等） |
| `https://comment-api.kkdzpt.com/api/v1/topic/topic_class` | GET | 200 | application/json | 话题分类（classId, className） |
| `https://comment-api.kkdzpt.com/api/v1/comment/comment_info?mapId=180750` | GET | 200 | application/json | 评论统计（评分分布等） |
| `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/comment/search?mapId=180750&sort=GREAT&...` | GET | 200 | application/json | 精选评论搜索 |
| `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/comment/map_score_summary?mapId=180750` | GET | 200 | application/json | 评分汇总 |
| `https://activity-api.kkdzpt.com/api/web/resource/find` | POST | 200 | application/json | 活动资源（需 POST，GET 返回 405） |
| `https://kk-web-gateway.kkdzpt.com/platform-map-api/api/cfg/switch` | GET | 200 | application/json | 平台配置开关 |

---

## 2) JSON 响应字段（重点接口）

### 2.1 地图详情 `map-api.kkdzpt.com/api/v2/map/detail?mapId=180750`

**可直接访问**，无需登录。

| 字段 | 示例值 | 说明 |
|------|--------|------|
| mapId | 180750 | 地图ID |
| mapName | 肉鸽地牢 | 地图名称 |
| mapVersion | 3.1.169 | 当前版本号 |
| war3Version | 1.27.0 | War3 版本 |
| mapType / mapTypeStr | 8 / 其他 | 地图类型 |
| tagsString | ["冒险"] | 标签 |
| playerCount | "2-4" | 玩家数 |
| createDate | "2021-01-14 10:00:26" | 创建时间 |
| updateTime | 1772182800000 | 更新时间戳 |
| authorInfo | { authorName: "郁子", authorAvatar, authorAccount } | 作者信息 |
| howToPlay | { summary, victory, advanced } | 地图说明（HTML） |
| score | 6.8 | 评分 |
| scoreCount | 4015 | 评分人数 |
| commentCount | 5888 | 评论数 |
| followerCount | 9940 | 关注数 |
| logo, adLogo, bigLogoList | URL | 图片资源 |

**缺失**：无版本更新日志、Boss 列表、关卡详情、波次信息等结构化数据。

### 2.2 社区攻略 / 评论 `topic/page_query_topics`

| 字段 | 说明 |
|------|------|
| topicId, title, content | 帖子标题、内容 |
| mapVersion | 发帖时的地图版本 |
| className | 分类：攻略、bug反馈、灌水、建议、其他 |
| releaseTime, browseCount, commentCount | 发布时间、浏览、评论数 |
| images | 图片 URL 列表 |

### 2.3 置顶话题 `topic/top_data`

返回置顶帖子（社区协议、攻略、bug 反馈等），格式与 `page_query_topics` 相同。

---

## 3) 可直接访问的详情接口与示例

### 3.1 地图详情（推荐）

```
GET https://map-api.kkdzpt.com/api/v2/map/detail?mapId=180750
```

**示例（核心字段）**：

```json
{
  "status": 200,
  "data": {
    "mapId": 180750,
    "mapName": "肉鸽地牢",
    "mapVersion": "3.1.169",
    "war3Version": "1.27.0",
    "mapTypeStr": "其他",
    "playerCount": "2-4",
    "authorInfo": { "authorName": "郁子" },
    "howToPlay": {
      "summary": "四名玩家各操控一个英雄，合作挑战各种BOSS和小怪...",
      "victory": "完成所有关卡",
      "advanced": "所有道具和天赋强化都是可叠加的..."
    },
    "score": 6.8,
    "scoreCount": 4015,
    "commentCount": 5888
  }
}
```

### 3.2 社区攻略列表

```
GET https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=180750&orderType=1&start=0&limit=10
```

参数：`start` 分页、`limit` 每页数量、`orderType` 排序。

### 3.3 评论统计

```
GET https://comment-api.kkdzpt.com/api/v1/comment/comment_info?mapId=180750
```

---

## 4) 结论：与网页正文的关系

| 内容类型 | 网页正文 | 官方 API | 说明 |
|----------|----------|----------|------|
| 地图名称、版本、作者 | ✓ | ✓ | API 与正文一致 |
| 地图说明（HTML） | ✓ | ✓ | howToPlay 中完整 |
| 版本更新日志 | ✗ | ✗ | 无 changelog 接口 |
| Boss / 关卡详情 | ✗ | ✗ | 无结构化数据 |
| 社区攻略 | 部分可见 | ✓ | 通过 topic API 可获取 |
| 评论 | 部分可见 | ✓ | 通过 comment API 可获取 |

**总结**：官方站 API 提供的地图元数据与网页正文一致，但**没有**版本更新日志、Boss 列表、关卡详情等结构化数据。游戏机制、敌人、Boss 等详情仍需依赖 rouge.wiki 等第三方数据源。
