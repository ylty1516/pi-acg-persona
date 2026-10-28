/**
 * Einx Breath — 柔和的思考呼吸指示器
 *
 * 把 pi 流式输出时的旋转 spinner 换成一颗会"呼吸"的光点。
 * 设计取向是「柔和」而不是「活泼」：
 *   - 不用 braille 旋转帧（⠋⠙⠹ 那种跳动的方哥，视觉上很吵）
 *   - 字号按 · → • → ● → • 缓慢胀缩，一个完整呼吸约 2.2 秒
 *   - 颜色在 borderMuted → border → accent 之间缓慢爬升再回落，
 *     全部取自当前主题的 token，换主题会自动跟着变
 *
 * 用法：
 *   放在 <agent-dir>/extensions/ 下，pi 启动自动加载
 *   临时试：pi --extension ./einx-breath.ts
 *
 * 命令：
 *   /breath          看当前状态
 *   /breath reset    恢复 pi 原生 spinner
 *   /breath fast     快一点（120ms）
 *   /breath slow     慢一点（260ms）
 */

import type { ExtensionAPI, ExtensionContext, WorkingIndicatorOptions } from "@earendil-works/pi-coding-agent";

// 一个完整呼吸的形状：小 → 大 → 小
const SHAPE = ["·", "·", "•", "•", "●", "●", "•", "•"] as const;

// 同一时刻的色阶：暗紫 → 中紫 → 樱花 → 中紫 → 暗紫
// 注意别把 dim 拼进来：dim 比 borderMuted 亮，插进去会让呼吸“先暗一下再亮”，变成抽搞
// 峰值（accent）停留两帧，呼吸才有停顿感而不是平滑三角波
const RAMP = [
	"borderMuted",
	"borderMuted",
	"border",
	"accent",
	"accent",
	"border",
	"borderMuted",
	"borderMuted",
] as const;

const DEFAULT_INTERVAL = 180;

type Speed = "default" | "fast" | "slow" | "off";

let speed: Speed = "default";

function intervalFor(s: Speed): number {
	if (s === "fast") return 120;
	if (s === "slow") return 260;
	return DEFAULT_INTERVAL;
}

/**
 * 颜色必须由我们自己上：setWorkingIndicator 的帧是原样输出的，
 * pi 不会替我们套主题色。
 */
function buildOptions(theme: ExtensionContext["ui"]["theme"]): WorkingIndicatorOptions {
	// 呼吸是由两段相位错开的循环叠出来的，比单向循环更像呼吸而不是转圈
	const frames = SHAPE.map((char, i) => theme.fg(RAMP[i]!, char));

	return { frames, intervalMs: intervalFor(speed) };
}

function apply(ctx: ExtensionContext) {
	if (!ctx.hasUI) return;
	// 主题在 RPC 等模式下可能不可用；指示器只是装饰，不能因为它把 session_start 弄报错
try {
		if (speed === "off") {
			ctx.ui.setWorkingIndicator(undefined);
			return;
		}
		const theme = ctx.ui.theme;
		if (!theme || typeof theme.fg !== "function") return;
		ctx.ui.setWorkingIndicator(buildOptions(theme));
	}
	catch {
		// 默默放弃：宁可回到 pi 原生 spinner，也不要每开一个会话弹一次错误
	}
}

function describe(): string {
	switch (speed) {
		case "off":
			return "pi 原生 spinner";
		case "fast":
			return "呼吸 · 120ms";
		case "slow":
			return "呼吸 · 260ms";
		default:
			return "呼吸 · 180ms";
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		apply(ctx);
	});

	pi.registerCommand("breath", {
		description: "思考指示器：reset / fast / slow / off",
		handler: async (args, ctx) => {
			if (!ctx.hasUI) {
				ctx.ui.notify("呼吸指示器需要交互模式", "error");
				return;
			}

			const next = args.trim().toLowerCase();

			if (!next) {
				ctx.ui.notify(`当前：${describe()}`, "info");
				return;
			}

			if (next === "reset") {
				speed = "default";
			}
			else if (next === "fast") {
				speed = "fast";
			}
			else if (next === "slow") {
				speed = "slow";
			}
			else if (next === "off") {
				speed = "off";
			}
			else {
				ctx.ui.notify("用法：/breath [reset|fast|slow|off]", "error");
				return;
			}

			apply(ctx);
			ctx.ui.notify(`思考指示器：${describe()}`, "info");
		},
	});
}
