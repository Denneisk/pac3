
local L = pace.LanguageString

local acsfnc = function(key, def)
	pace["View" .. key] = def
	pace["SetView" .. key] = function(val) pace["View" .. key] = val end
	pace["GetView" .. key] = function() return pace["View" .. key] or def end
end

acsfnc("Entity", NULL)
acsfnc("Pos", Vector(5,5,5))
acsfnc("Angles", Angle(0,0,0))
acsfnc("FOV", 75)

pace.camera_forward_bind = CreateClientConVar("pac_editor_camera_forward_bind", "w", true)
pace.camera_back_bind = CreateClientConVar("pac_editor_camera_back_bind", "s", true)
pace.camera_moveleft_bind = CreateClientConVar("pac_editor_camera_moveleft_bind", "a", true)
pace.camera_moveright_bind = CreateClientConVar("pac_editor_camera_moveright_bind", "d", true)
pace.camera_up_bind = CreateClientConVar("pac_editor_camera_up_bind", "space", true)
pace.camera_down_bind = CreateClientConVar("pac_editor_camera_down_bind", "", true)
pace.camera_slow_bind = CreateClientConVar("pac_editor_camera_slow_bind", "ctrl", true)
pace.camera_speed_bind = CreateClientConVar("pac_editor_camera_speed_bind", "shift", true)

pace.camera_movement_binds = {
	["forward"] = pace.camera_forward_bind,
	["back"] = pace.camera_back_bind,
	["moveleft"] = pace.camera_moveleft_bind,
	["moveright"] = pace.camera_moveright_bind,
	["up"] = pace.camera_up_bind,
	["down"] = pace.camera_down_bind,
	["slow"] = pace.camera_slow_bind,
	["speed"] = pace.camera_speed_bind
}

function pace.GetViewEntity()
	return pace.ViewEntity:IsValid() and pace.ViewEntity or pac.LocalPlayer
end

function pace.ResetView()
	if pace.Focused then
		local ent = pace.GetViewEntity()

		if not ent:IsValid() then
			local _, part = next(pac.GetLocalParts())
			if part then
				ent = part:GetOwner()
			end
		end

		if ent:IsValid() then
			local fwd = ent.EyeAngles and ent:EyeAngles() or ent:GetAngles()

			-- Source Engine local angles fix
			if ent == pac.LocalPlayer and ent:GetVehicle():IsValid() then
				local ang = ent:GetVehicle():GetAngles()
				fwd = fwd + ang
			end

			fwd = fwd:Forward()
			fwd.z = 0
			pace.ViewPos = ent:EyePos() + fwd * 128
			pace.ViewAngles = (ent:EyePos() - pace.ViewPos):Angle()
			pace.ViewAngles:Normalize()
		end
	end
end

function pace.SetZoom(fov, smooth)
	if smooth then
		pace.ViewFOV = Lerp(FrameTime()*10, pace.ViewFOV, math.Clamp(fov,1,100))
	else
		pace.ViewFOV = math.Clamp(fov,1,100)
	end
end

function pace.ResetZoom()
	pace.zoom_reset = 75
end

local worldPanel = vgui.GetWorldPanel();
function worldPanel.OnMouseWheeled( self, scrollDelta )
	if IsValid(pace.Editor) then
		local zoom_usewheel = GetConVar( "pac_zoom_mousewheel" )

		if zoom_usewheel:GetInt() == 1 then
			local speed = 10

			if input.IsKeyDown(KEY_LSHIFT) then
				speed = 50
			end

			if input.IsKeyDown(KEY_LCONTROL) then
				speed = 1
			end

			if vgui.GetHoveredPanel() == worldPanel then
				pace.Editor.zoomslider:SetValue(pace.ViewFOV - (scrollDelta * speed))
			end
		end
	end
end

local held_ang = Angle(0,0,0)
local held_mpos = Vector(0,0,0)
local mcode, hoveredPanelCursor, isHoldingMovement

function pace.GUIMousePressed(mc)
	if pace.mctrl.GUIMousePressed(mc) then return end

	if mc == MOUSE_LEFT and not pace.editing_viewmodel then
		held_ang = pace.ViewAngles * 1
		held_mpos = Vector(input.GetCursorPos())
	end

	if mc == MOUSE_RIGHT then
		pace.Call("OpenMenu")
	end

	hoveredPanelCursor = vgui.GetHoveredPanel()

	if IsValid(hoveredPanelCursor) then
		hoveredPanelCursor:SetCursor('sizeall')
	end

	mcode = mc
	isHoldingMovement = true
end

function pace.GUIMouseReleased(mc)
	isHoldingMovement = false

	if IsValid(hoveredPanelCursor) then
		hoveredPanelCursor:SetCursor('arrow')
		hoveredPanelCursor = nil
	end

	if pace.mctrl.GUIMouseReleased(mc) then return end

	if pace.editing_viewmodel or pace.editing_hands then return end

	mcode = nil
end

local function set_mouse_pos(x, y)
	input.SetCursorPos(x, y)
	held_ang = pace.ViewAngles * 1
	held_mpos = Vector(x, y)
	return held_mpos * 1
end

local WORLD_ORIGIN = Vector(0, 0, 0)

local function MovementBindDown(name)
	return input.IsButtonDown(input.GetKeyCode(pace.camera_movement_binds[name]:GetString()))
end

local function CalcDrag()
	if not pace.properties or not pace.properties.search then return end

	if
		pace.BusyWithProperties:IsValid() or
		pace.ActiveSpecialPanel:IsValid() or
		pace.editing_viewmodel or
		pace.editing_hands or
		pace.properties.search:HasFocus()
	then return end

	local focus = vgui.GetKeyboardFocus()
	if focus and focus:IsValid() and focus:GetName():lower():find('textentry') then return end

	if not system.HasFocus() then
		held_mpos = Vector(input.GetCursorPos())
	end

	local ftime = FrameTime() * 50
	local mult = 5

	if MovementBindDown("slow") then
		mult = 0.1
	end

	local origin
	local part = pace.current_part or NULL

	if not part:IsValid() then return end

	local owner = part:GetRootPart():GetOwner()
	if not owner:IsValid() then
		owner = pac.LocalPlayer
	end

	origin = owner:GetPos()
	if owner == pac.WorldEntity then
		if part:HasChildren() then
			for key, child in ipairs(part:GetChildren()) do
				if child.GetDrawPosition then
					part = child
					break
				end
			end
		end
	end

	if part.GetDrawPosition then
		origin = part:GetDrawPosition()
	end

	if not origin or origin == WORLD_ORIGIN then
		origin = pac.LocalPlayer:GetPos()
	end

	mult = mult * math.min(origin:Distance(pace.ViewPos) / 200, 3)

	if MovementBindDown("speed") then
		mult = mult + 5
	end

	if not pace.IsSelecting then
		if mcode == MOUSE_LEFT then
			local mpos = Vector(input.GetCursorPos())

			if mpos.x >= ScrW() - 1 then
				mpos = set_mouse_pos(1, gui.MouseY())
			elseif mpos.x < 1 then
				mpos = set_mouse_pos(ScrW() - 2, gui.MouseY())
			end

			if mpos.y >= ScrH() - 1 then
				mpos = set_mouse_pos(gui.MouseX(), 1)
			elseif mpos.y < 1 then
				mpos = set_mouse_pos(gui.MouseX(), ScrH() - 2)
			end

			local delta = (held_mpos - mpos) / 5 * math.rad(pace.ViewFOV)
			pace.ViewAngles.p = math.Clamp(held_ang.p - delta.y, -90, 90)
			pace.ViewAngles.y = held_ang.y + delta.x
		end
	end


	if pace.delaymovement < RealTime() then
		if MovementBindDown("forward") then
			pace.ViewPos = pace.ViewPos + pace.ViewAngles:Forward() * mult * ftime
		elseif  MovementBindDown("back") then
			pace.ViewPos = pace.ViewPos - pace.ViewAngles:Forward() * mult * ftime
		end

		if  MovementBindDown("moveright") then
			pace.ViewPos = pace.ViewPos + pace.ViewAngles:Right() * mult * ftime
		elseif  MovementBindDown("moveleft") then
			pace.ViewPos = pace.ViewPos - pace.ViewAngles:Right() * mult * ftime
		end

		if  MovementBindDown("up") then
			if not IsValid(pace.timeline.frame) then
				pace.ViewPos = pace.ViewPos + pace.ViewAngles:Up() * mult * ftime
			end
		elseif  MovementBindDown("down") then
			if not IsValid(pace.timeline.frame) then
				pace.ViewPos = pace.ViewPos - pace.ViewAngles:Up() * mult * ftime
			end
		end
	end

end

local follow_entity = CreateClientConVar("pac_camera_follow_entity", "0", true)
local enable_editor_view = CreateClientConVar("pac_enable_editor_view", "1", true)
cvars.AddChangeCallback("pac_enable_editor_view", function(name, old, new)
	if new == "1" then
		pace.EnableView(true)
	else
		pace.CameraPartSwapView()
	end
end, "pace_update_editor_view")

local lastEntityPos

function pace.CalcView(ply, pos, ang, fov)
	if pace.editing_viewmodel or pace.editing_hands then
		pace.ViewPos = pos
		pace.ViewAngles = ang
		pace.ViewFOV = fov
	return end

	if follow_entity:GetBool() then
		local ent = pace.GetViewEntity()
		local pos = ent:GetPos()
		lastEntityPos = lastEntityPos or pos
		pace.ViewPos = pace.ViewPos + pos - lastEntityPos
		lastEntityPos = pos
	else
		lastEntityPos = nil
	end

	local pos, ang, fov = pac.CallHook("EditorCalcView", pace.ViewPos, pace.ViewAngles, pace.ViewFOV)

	if pos then
		pace.ViewPos = pos
	end

	if ang then
		pace.ViewAngles = ang
	end

	if fov then
		pace.ViewFOV = fov
	end

	return
	{
		origin = pace.ViewPos,
		angles = pace.ViewAngles,
		fov = pace.ViewFOV,
	}
end

function pace.ShouldDrawLocalPlayer()
	if not pace.editing_viewmodel and not pace.editing_hands then
		return true
	end
end

local notifText
local notifDisplayTime, notifDisplayTimeFade = 0, 0

function pace.FlashNotification(text, timeToDisplay)
	timeToDisplay = timeToDisplay or math.Clamp(#text / 6, 1, 8)
	notifDisplayTime = RealTime() + timeToDisplay
	notifDisplayTimeFade = RealTime() + timeToDisplay * 1.1
	notifText = text
end

function pace.PostRenderVGUI()
	if not pace.mctrl then return end

	local time = RealTime()

	if notifDisplayTimeFade > time then
		if notifDisplayTime > time then
			surface.SetTextColor(color_white)
		else
			surface.SetTextColor(255, 255, 255, 255 * (notifDisplayTimeFade - RealTime()) / (notifDisplayTimeFade - notifDisplayTime))
		end

		surface.SetFont('Trebuchet18')
		local w = surface.GetTextSize(notifText)
		surface.SetTextPos(ScrW() / 2 - w / 2, 30)
		surface.DrawText(notifText)
	end

	if not isHoldingMovement then return end

	if pace.mctrl.LastThinkCall ~= FrameNumber() then
		surface.SetFont('Trebuchet18')
		surface.SetTextColor(color_white)
		local text = L'You are currently holding the camera, movement is disabled'
		local w = surface.GetTextSize(text)
		surface.SetTextPos(ScrW() / 2 - w / 2, 10)
		surface.DrawText(text)
	end
end

function pace.EnableView(b)
	if b then
		pac.AddHook("GUIMousePressed", "editor", pace.GUIMousePressed)
		pac.AddHook("GUIMouseReleased", "editor", pace.GUIMouseReleased)
		pac.AddHook("ShouldDrawLocalPlayer", "editor", pace.ShouldDrawLocalPlayer, DLib and -4 or ULib and -1 or nil)
		if enable_editor_view:GetBool() then
			pac.AddHook("CalcView", "editor", pace.CalcView, DLib and -4 or ULib and -1 or nil)
			pac.RemoveHook("CalcView", "camera_part")
			pac.active_camera = nil
		else
			if pac.HasRemainingCameraPart() then pace.CameraPartSwapView() end
			pac.RemoveHook("CalcView", "editor")
		end
		pac.AddHook("HUDPaint", "editor", pace.HUDPaint)
		pac.AddHook("HUDShouldDraw", "editor", pace.HUDShouldDraw)
		pac.AddHook("PostRenderVGUI", "editor", pace.PostRenderVGUI)
		pace.Focused = true
		pace.ResetView()
	else
		lastEntityPos = nil
		pac.RemoveHook("GUIMousePressed", "editor")
		pac.RemoveHook("GUIMouseReleased", "editor")
		pac.RemoveHook("ShouldDrawLocalPlayer", "editor")
		pac.RemoveHook("CalcView", "editor")
		pac.AddHook("CalcView", "camera_part", pac.HandleCameraPart)
		pac.RemoveHook("HUDPaint", "editor")
		pac.RemoveHook("HUDShouldDraw", "editor")
		pac.RemoveHook("PostRenderVGUI", "editor")
		pace.SetTPose(false)
	end
end

function pace.ManuallySelectCamera(obj, doselect)
	if obj and doselect then
		obj:CameraTakePriority(true)
		pace.CameraPartSwapView(true)
		pac.active_camera_manual = obj
	elseif not doselect then
		for i,v in pairs(pac.GetLocalParts()) do
			if v.ClassName == "camera" then
				if not v:IsHidden() and v ~= obj then
					v:CameraTakePriority(true)
					pace.CameraPartSwapView(true)
					pac.active_camera_manual = v
					return
				end
			end
		end
		pac.active_camera_manual = nil
	else
		for i,v in pairs(pac.GetLocalParts()) do
			if v.ClassName == "camera" then
				if not v:IsHidden() then
					v:CameraTakePriority(true)
					pace.CameraPartSwapView(true)
					pac.active_camera_manual = v
					return
				end
			end
		end
	end
end

function pace.CameraPartSwapView(force_pac_camera)
	local pac_camera_parts_should_override = not enable_editor_view:GetBool() or not pace.Editor:IsValid() or pac.HasRemainingCameraPart()

	if pace.Editor:IsValid() and enable_editor_view:GetBool() and not force_pac_camera then pac_camera_parts_should_override = false end

	if pac.HandleCameraPart() == nil then --no cameras
		if not pace.ShouldDrawLocalPlayer() then
			pace.EnableView(false)
		end
		pac.RemoveHook("CalcView", "camera_part")
	elseif pac_camera_parts_should_override then --cameras
		pac.AddHook("CalcView", "camera_part", pac.HandleCameraPart)
		pac.RemoveHook("CalcView", "editor")
	else
		pace.EnableView(enable_editor_view:GetBool())
		--[[if not GetConVar("pac_copilot_force_preview_cameras"):GetBool() then
			
		else
			pace.EnableView(false)
		end]]
	end


	return pac.active_camera
end

local function CalcAnimationFix(ent)
	if ent.SetEyeAngles then
		ent:SetEyeAngles(Angle(0,0,0))
	end
end

local reset_pose_params =
{
	"body_rot_z",
	"spine_rot_z",
	"head_rot_z",
	"head_rot_y",
	"head_rot_x",
	"walking",
	"running",
	"swimming",
	"rhand",
	"lhand",
	"rfoot",
	"lfoot",
	"move_yaw",
	"aim_yaw",
	"aim_pitch",
	"breathing",
	"vertical_velocity",
	"vehicle_steer",
	"body_yaw",
	"spine_yaw",
	"head_yaw",
	"head_pitch",
	"head_roll",
}

function pace.GetTPose()
	return pace.tposed
end

function pace.SetViewPart(part, reset_campos)
	pace.SetViewEntity(part:GetRootPart():GetOwner())

	if reset_campos then
		pace.ResetView()
	end
end

function pace.HUDPaint()
	if mcode and not input.IsMouseDown(mcode) then
		mcode = nil
	end

	local ent = pace.GetViewEntity()

	if pace.IsFocused() then
		CalcDrag()

		if ent:IsValid() then
			pace.Call("Draw", ScrW(), ScrH())
		end
	end
end

function pace.HUDShouldDraw(typ)
	if
		typ == "CHudEPOE" or
		(typ == "CHudCrosshair" and (pace.editing_viewmodel or pace.editing_hands))
	then
		return false
	end
end

function pace.OnToggleFocus(show_editor)
	if pace.Focused then
		pace.KillFocus(show_editor)
	else
		pace.GainFocus(show_editor)
	end
end

function pace.SetTPose(b)
	local ply = pac.LocalPlayer

	if b then
		ply.pace_tpose_last_sequence = ply:GetSequence()
		ply.pace_tpose_last_layer_sequence = {}
		for i = 0, 16 do
			ply.pace_tpose_last_layer_sequence[i] = ply:GetLayerSequence(i)
		end

		local function reset_angles(ply)
			local ang = ply:EyeAngles()
			ang.p = 0
			ply:SetEyeAngles(ang)
			ply:SetRenderAngles(ang)
			ply:SetAngles(ang)
		end

		local function get_ref_anim(ply)
			local id = ply:LookupSequence("reference")
			local id2 = ply:LookupSequence("ragdoll")
			return id ~= -1 and id or id2 ~= -1 and id2 or 0
		end

		pac.AddHook("PrePlayerDraw", "pace_tpose", function(ply)
			if ply ~= pac.LocalPlayer then return end

			for i = 0, 16 do
				ply:SetLayerSequence(i, 0)
			end

			ply:SetSequence(get_ref_anim(ply))
			reset_angles(ply)
		end)

		pac.AddHook("UpdateAnimation", "pace_tpose", function()
			local ply = pac.LocalPlayer
			ply:ClearPoseParameters()
			reset_angles(ply)

			for i = 0, ply:GetNumPoseParameters() - 1 do
				local name = ply:GetPoseParameterName(i)
				if name then
					ply:SetPoseParameter(name, 0)
				end
			end
		end)

		pac.AddHook("CalcMainActivity", "pace_tpose", function(ply)
			if ply == pac.LocalPlayer then
				for i = 0, 16 do
					ply:SetLayerSequence(i, 0)
				end

				local act = get_ref_anim(ply)

				return act, act
			end
		end)
	else
		pac.RemoveHook("PrePlayerDraw", "pace_tpose")
		pac.RemoveHook("UpdateAnimation", "pace_tpose")
		pac.RemoveHook("CalcMainActivity", "pace_tpose")

		if ply.pace_tpose_last_sequence then
			ply:SetSequence(ply.pace_tpose_last_sequence)
			ply.pace_tpose_last_sequence = nil
		end

		if ply.pace_tpose_last_layer_sequence then
			for i, seq in ipairs(ply.pace_tpose_last_layer_sequence) do
				ply:SetLayerSequence(i, seq)
			end

			ply.pace_tpose_last_layer_sequence = nil
		end
	end

	pace.tposed = b
end

pace.SetTPose(pace.tposed)

function pace.ToggleCameraFollow()
	local c = GetConVar("pac_camera_follow_entity")
	RunConsoleCommand("pac_camera_follow_entity", c:GetBool() and "0" or "1")
end

function pace.GetBreathing()
	return pace.breathing
end
function pace.ResetEyeAngles()
	local ent = pace.GetViewEntity()
	if ent:IsValid() then
		if ent:IsPlayer() then

			RunConsoleCommand("+forward")
			timer.Simple(0, function()
				RunConsoleCommand("-forward")
				timer.Simple(0.1, function()
					RunConsoleCommand("+back")
					timer.Simple(0.015, function()
						RunConsoleCommand("-back")
					end)
				end)
			end)

			ent:SetEyeAngles(Angle(0, 0, 0))
		else
			ent:SetAngles(Angle(0, 0, 0))
		end

		pac.SetupBones(ent)
	end
end

function pace.PopupMiniFOVSlider()
	zoom_persistent = GetConVar("pac_zoom_persistent")
	zoom_smooth = GetConVar("pac_zoom_smooth")
	local zoomframe = vgui.Create( "DPanel" )
	local x,y = input.GetCursorPos()
	zoomframe:SetPos(x - 90,y - 10)
	zoomframe:SetSize( 180, 20 )

	zoomframe.zoomslider = vgui.Create("DNumSlider", zoomframe)
	zoomframe.zoomslider:DockPadding(4,0,0,0)
	zoomframe.zoomslider:SetSize(200, 20)
	zoomframe.zoomslider:SetMin( 0 )
	zoomframe.zoomslider:SetMax( 100 )
	zoomframe.zoomslider:SetDecimals( 0 )
	zoomframe.zoomslider:SetText("Camera FOV")
	zoomframe.zoomslider:SetDark(true)
	zoomframe.zoomslider:SetDefaultValue( 75 )

	zoomframe.zoomslider:SetValue( pace.ViewFOV )

	function zoomframe:Think(...)
		pace.ViewFOV = zoomframe.zoomslider:GetValue()
		if zoom_smooth:GetInt() == 1 then
			pace.SetZoom(zoomframe.zoomslider:GetValue(),true)
		else
			pace.SetZoom(zoomframe.zoomslider:GetValue(),false)
		end
	end

	local hook_id = "pac_tools_menu"..util.SHA256(tostring(zoomframe))

	pac.AddHook("VGUIMousePressed", hook_id, function(pnl, code)
		pace.OverridingFOVSlider = true --to link the values with the original panel in the pac editor panel
		if not IsValid(zoomframe) then
			pac.RemoveHook("VGUIMousePressed", hook_id)
			return
		end
		if code == MOUSE_LEFT or code == MOUSE_RIGHT then
			if not zoomframe:IsOurChild(pnl) then
				if zoomframe.zoomslider then zoomframe.zoomslider:Remove() end
				zoomframe:Remove()
				pac.RemoveHook("VGUIMousePressed", hook_id)
				pace.OverridingFOVSlider = false
			end
		end
	end)

end
