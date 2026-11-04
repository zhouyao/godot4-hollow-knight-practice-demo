extends CanvasLayer
class_name DeathScreen

## 死亡结算遮罩：黑场淡入 + 3 秒倒数，倒数结束后由调用方切回存档选择页。
##
## process_mode = ALWAYS：此时整棵场景树已经被暂停（游戏冻结），
## 本层必须继续处理，否则黑场淡入和倒数都不会动。

## 倒数秒数。
const COUNTDOWN_SECONDS := 5

## 黑场最终不透明度：留一点画面轮廓，避免全黑。
const BACKDROP_ALPHA := 0.78

@onready var backdrop: ColorRect = $Backdrop
@onready var count_label: Label = $Center/VBox/CountLabel


func _ready() -> void:
	Tr.apply(self)
	count_label.text = str(COUNTDOWN_SECONDS)


## 播黑场淡入与倒数，全部结束后返回；调用方 await play() 即可接着切场景。
func play() -> void:
	var tween := create_tween()
	# 暂停状态下也要推进淡入。
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(backdrop, "color:a", BACKDROP_ALPHA, 0.3)
	for remaining in range(COUNTDOWN_SECONDS, 0, -1):
		count_label.text = str(remaining)
		await get_tree().create_timer(1.0).timeout
