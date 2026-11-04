extends VBoxContainer
class_name AudioContent


@onready var _header: SectionHeader = $Header


## 花纹重播统一由 SectionHeader 负责（它自己监听可见性变化）；
## 保留这个入口给“已经停在音频页、再点一次音频 tab”的调用方。
func play_intro() -> void:
	_header.play_intro()
