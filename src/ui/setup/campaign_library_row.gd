## Presents a compact campaign row without confusing focus with a prepared selection.
class_name CampaignLibraryRow
extends PanelContainer

signal campaign_pressed
var _campaign_path := ""

func _ready() -> void:
	%LaunchCampaign.pressed.connect(func() -> void: campaign_pressed.emit())

func configure(campaign: CampaignPackageView, selected: bool, operation_running: bool, _focused: bool) -> void:
	_campaign_path = campaign.path
	var title := campaign.display_name if not campaign.display_name.is_empty() else campaign.campaign_id
	%LaunchCampaign.text = ("✓ " if selected else "") + title
	%LaunchCampaign.tooltip_text = "%s\n%s" % [title, "Ready with compatibility warnings" if campaign.ready_with_warnings else "Ready" if campaign.ready else campaign.error_message]
	%LaunchCampaign.disabled = operation_running
	%LaunchCampaign.set_pressed_no_signal(selected)

func package_path() -> String:
	return _campaign_path
