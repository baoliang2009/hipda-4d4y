#!/usr/bin/env python3
"""
4D4Y 论坛 App 图标生成器 v2.0
现代简约设计，符合设计美学
"""

from PIL import Image, ImageDraw, ImageFont
import math

def create_modern_icon():
    """创建现代简约风格的图标"""
    size = 1024

    # 创建带透明通道的图像
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 主色调：现代蓝紫渐变
    # 背景：深邃的渐变 (#5B86E5 -> #36D1DC)
    for y in range(size):
        progress = y / size
        # 从蓝紫到青蓝的渐变
        r = int(91 + (54 - 91) * progress)
        g = int(134 + (209 - 134) * progress)
        b = int(229 + (220 - 229) * progress)
        draw.rectangle([(0, y), (size, y+1)], fill=(r, g, b, 255))

    # 添加微妙的噪点质感
    import random
    random.seed(42)
    for _ in range(2000):
        x = random.randint(0, size-1)
        y = random.randint(0, size-1)
        alpha = random.randint(10, 30)
        current_color = img.getpixel((x, y))
        new_color = (
            min(255, current_color[0] + random.randint(-10, 10)),
            min(255, current_color[1] + random.randint(-10, 10)),
            min(255, current_color[2] + random.randint(-10, 10)),
            255
        )
        draw.point((x, y), fill=new_color)

    # 绘制几何装饰元素 - 立体方块
    center_x, center_y = size // 2, size // 2 - int(size * 0.05)

    # 方块尺寸
    cube_size = int(size * 0.35)

    # 绘制 3D 方块效果
    # 顶面 (菱形)
    top_points = [
        (center_x, center_y - cube_size // 2),  # 上
        (center_x + cube_size // 2, center_y - cube_size // 4),  # 右
        (center_x, center_y),  # 下
        (center_x - cube_size // 2, center_y - cube_size // 4),  # 左
    ]
    draw.polygon(top_points, fill=(255, 255, 255, 240))

    # 左侧面
    left_points = [
        (center_x - cube_size // 2, center_y - cube_size // 4),  # 上
        (center_x - cube_size // 2, center_y + cube_size // 4),  # 下
        (center_x, center_y + cube_size // 2),  # 右下
        (center_x, center_y),  # 右上
    ]
    draw.polygon(left_points, fill=(230, 235, 245, 240))

    # 右侧面
    right_points = [
        (center_x, center_y),  # 左上
        (center_x, center_y + cube_size // 2),  # 左下
        (center_x + cube_size // 2, center_y + cube_size // 4),  # 右下
        (center_x + cube_size // 2, center_y - cube_size // 4),  # 右上
    ]
    draw.polygon(right_points, fill=(210, 220, 240, 240))

    # 添加细节边框
    draw.line(top_points + [top_points[0]], fill=(200, 210, 230, 255), width=2)
    draw.line(left_points + [left_points[0]], fill=(180, 190, 210, 255), width=2)
    draw.line(right_points + [right_points[0]], fill=(180, 190, 210, 255), width=2)

    # 绘制文字 "4D4Y" - 使用更现代的排版
    try:
        # 使用粗体字体
        font_size = int(size * 0.16)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except:
            try:
                font = ImageFont.truetype("/System/Library/Fonts/Arial Bold.ttf", font_size)
            except:
                font = ImageFont.load_default()
    except:
        font = ImageFont.load_default()

    text = "4D4Y"

    # 获取文字尺寸
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # 文字位置 (在方块上方)
    text_x = center_x - text_width // 2
    text_y = center_y - cube_size // 2 - text_height - int(size * 0.05)

    # 绘制文字阴影 (多层，更柔和)
    for offset in range(4, 0, -1):
        alpha = 30 - offset * 5
        draw.text(
            (text_x + offset, text_y + offset),
            text,
            font=font,
            fill=(0, 0, 0, alpha)
        )

    # 绘制主文字 (白色)
    draw.text(
        (text_x, text_y),
        text,
        font=font,
        fill=(255, 255, 255, 255)
    )

    # 绘制装饰线条
    line_y = center_y - cube_size // 2 - int(size * 0.02)
    line_width = int(size * 0.25)
    line_x_start = center_x - line_width // 2
    line_x_end = center_x + line_width // 2

    # 渐变线条
    for i in range(3):
        offset = i * 2
        alpha = 255 - i * 80
        draw.line(
            [(line_x_start, line_y + offset), (line_x_end, line_y + offset)],
            fill=(255, 255, 255, alpha),
            width=2
        )

    # 底部小标签
    try:
        tag_font_size = int(size * 0.045)
        try:
            tag_font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", tag_font_size)
        except:
            tag_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", tag_font_size)
    except:
        tag_font = font

    tag_text = "FORUM"
    tag_bbox = draw.textbbox((0, 0), tag_text, font=tag_font)
    tag_width = tag_bbox[2] - tag_bbox[0]
    tag_height = tag_bbox[3] - tag_bbox[1]

    tag_x = center_x - tag_width // 2
    tag_y = center_y + cube_size // 2 + int(size * 0.08)

    # 标签背景
    padding = int(size * 0.02)
    tag_bg = [
        tag_x - padding,
        tag_y - padding // 2,
        tag_x + tag_width + padding,
        tag_y + tag_height + padding // 2
    ]
    draw.rounded_rectangle(tag_bg, radius=tag_height // 2, fill=(255, 255, 255, 180))

    # 标签文字
    draw.text(
        (tag_x, tag_y),
        tag_text,
        font=tag_font,
        fill=(91, 134, 229, 255)
    )

    # 添加点缀元素 - 小圆点
    dot_positions = [
        (int(size * 0.15), int(size * 0.2)),
        (int(size * 0.85), int(size * 0.25)),
        (int(size * 0.2), int(size * 0.8)),
        (int(size * 0.8), int(size * 0.75)),
    ]

    for pos in dot_positions:
        draw.ellipse(
            [pos[0] - 4, pos[1] - 4, pos[0] + 4, pos[1] + 4],
            fill=(255, 255, 255, 150)
        )

    return img

def main():
    print("🎨 正在生成现代简约风格的 4D4Y 图标...")

    icon = create_modern_icon()

    # 保存路径
    output_path = "/Users/liangbao/Desktop/Code/hipda/FourD4Y/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png"

    # 转换为 RGB
    rgb_icon = Image.new('RGB', icon.size, (255, 255, 255))
    if icon.mode == 'RGBA':
        rgb_icon.paste(icon, mask=icon.split()[3])
    else:
        rgb_icon.paste(icon)

    # 保存
    rgb_icon.save(output_path, 'PNG', quality=100, optimize=True)

    print(f"✅ 现代简约图标已生成")
    print(f"📏 尺寸: 1024x1024")
    print(f"🎨 设计风格: 3D立体方块 + 渐变背景")
    print(f"💡 配色: 蓝紫渐变 (#5B86E5 -> #36D1DC)")
    print(f"\n在 Xcode 中 Clean Build 后重新运行即可看到新图标！")

if __name__ == '__main__':
    main()
