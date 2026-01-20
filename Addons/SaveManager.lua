local httpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local SaveManager = {} do
	SaveManager.Folder = "FluentSettings"
	SaveManager.Ignore = {}
	SaveManager._configCache = {} -- ✅ Cache untuk fast load
	SaveManager._saveQueue = {} -- ✅ Queue untuk batch save
	SaveManager._isSaving = false
	SaveManager._isLoading = false
	
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				return { type = "Toggle", idx = idx, value = object.Value } 
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = "Slider", idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				return { type = "Dropdown", idx = idx, value = object.Value, mutli = object.Multi }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Colorpicker = {
			Save = function(idx, object)
				return { type = "Colorpicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
				end
			end,
		},
		Keybind = {
			Save = function(idx, object)
				return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.key, data.mode)
				end
			end,
		},
		Input = {
			Save = function(idx, object)
				return { type = "Input", idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] and type(data.text) == "string" then
					SaveManager.Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	-- ✅ OPTIMIZED SAVE: Async dengan compression
	function SaveManager:Save(name)
		if (not name) then
			return false, "no config file is selected"
		end

		-- ✅ Prevent multiple saves at once
		if self._isSaving then
			warn("[SaveManager] Save already in progress, queueing...")
			table.insert(self._saveQueue, name)
			return true
		end

		self._isSaving = true

		-- ✅ Run save in background thread
		spawn(function()
			local success, result = pcall(function()
				local fullPath = self.Folder .. "/settings/" .. name .. ".json"

				local data = {
					objects = {},
					version = "1.0",
					timestamp = os.time()
				}

				-- ✅ Collect data (skip empty values)
				local objectCount = 0
				for idx, option in next, SaveManager.Options do
					if not self.Parser[option.Type] then continue end
					if self.Ignore[idx] then continue end

					local savedData = self.Parser[option.Type].Save(idx, option)
					
					-- ✅ Skip default values untuk compression
					if savedData and savedData.value ~= nil and savedData.value ~= false and savedData.value ~= "" then
						table.insert(data.objects, savedData)
						objectCount = objectCount + 1
					end
				end

				-- ✅ Encode JSON
				local encoded = httpService:JSONEncode(data)
				
				-- ✅ Write to file
				writefile(fullPath, encoded)
				
				-- ✅ Update cache
				self._configCache[name] = data
				
				print("[SaveManager] ✅ Saved", objectCount, "settings to", name, "("..#encoded.." bytes)")
				
				return true
			end)

			self._isSaving = false

			-- ✅ Process queued saves
			if #self._saveQueue > 0 then
				local nextSave = table.remove(self._saveQueue, 1)
				task.wait(0.1)
				self:Save(nextSave)
			end

			if not success then
				warn("[SaveManager] Save error:", result)
				return false, "failed to save: " .. tostring(result)
			end
		end)

		return true
	end

	-- ✅ ULTRA-FAST LOAD: Chunked processing
	function SaveManager:Load(name)
		if (not name) then
			return false, "no config file is selected"
		end

		if self._isLoading then
			warn("[SaveManager] Load already in progress")
			return false, "load in progress"
		end

		self._isLoading = true
		
		local file = self.Folder .. "/settings/" .. name .. ".json"
		if not isfile(file) then 
			self._isLoading = false
			return false, "invalid file" 
		end

		-- ✅ Run load in background thread
		spawn(function()
			local success, result = pcall(function()
				local decoded

				-- ✅ Check cache first
				if self._configCache[name] then
					print("[SaveManager] ⚡ Using cached config:", name)
					decoded = self._configCache[name]
				else
					-- ✅ Read and decode file
					local fileContent = readfile(file)
					decoded = httpService:JSONDecode(fileContent)
					
					-- ✅ Cache it
					self._configCache[name] = decoded
				end

				if not decoded or not decoded.objects then
					return false, "invalid config format"
				end

				local totalOptions = #decoded.objects
				print("[SaveManager] Loading", totalOptions, "settings from", name)

				-- ✅ CHUNKED LOADING: Process in batches to avoid freeze
				local chunkSize = 15 -- Load 15 options per frame
				local currentIndex = 1

				local function loadChunk()
					local endIndex = math.min(currentIndex + chunkSize - 1, totalOptions)
					local loadedCount = 0

					for i = currentIndex, endIndex do
						local option = decoded.objects[i]
						
						if option and self.Parser[option.type] then
							-- ✅ Safe load with pcall
							local ok = pcall(function()
								self.Parser[option.type].Load(option.idx, option)
								loadedCount = loadedCount + 1
							end)
							
							if not ok then
								-- Silent fail for missing options
							end
						end
					end

					currentIndex = endIndex + 1

					-- ✅ Continue to next chunk
					if currentIndex <= totalOptions then
						RunService.Heartbeat:Wait() -- Yield to next frame
						loadChunk()
					else
						-- ✅ All loaded
						print("[SaveManager] ✅ Loaded", loadedCount, "/", totalOptions, "settings")
						self._isLoading = false
					end
				end

				-- ✅ Start chunked loading
				loadChunk()

				return true
			end)

			if not success then
				warn("[SaveManager] Load error:", result)
				self._isLoading = false
				return false, "decode error: " .. tostring(result)
			end
		end)

		return true
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({ 
			"InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind"
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. "/settings"
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. "/settings")

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local pos = file:find(".json", 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= "/" and char ~= "\\" and char ~= "" do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == "/" or char == "\\" then
					local name = file:sub(pos + 1, start - 1)
					if name ~= "options" and name ~= "autoload" then
						table.insert(out, name)
					end
				end
			end
		end
		
		return out
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options
	end

	-- ✅ OPTIMIZED: Auto-load dengan delay
	function SaveManager:LoadAutoloadConfig()
		if isfile(self.Folder .. "/settings/autoload.txt") then
			local name = readfile(self.Folder .. "/settings/autoload.txt")

			print("[SaveManager] Auto-loading config:", name)

			-- ✅ Load in background dengan delay kecil
			task.delay(0.5, function()
				local success, err = self:Load(name)
				
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to load autoload config: " .. tostring(err),
						Duration = 7
					})
				end

				-- ✅ Show notification setelah 1 detik (biar load selesai dulu)
				task.delay(1, function()
					self.Library:Notify({
						Title = "Interface",
						Content = "Config loader ⚡",
						SubContent = string.format("Auto loaded config %q", name),
						Duration = 5
					})
				end)
			end)
		end
	end

	-- ✅ CLEAR CACHE: Call ini jika butuh free memory
	function SaveManager:ClearCache()
		self._configCache = {}
		print("[SaveManager] Cache cleared")
	end

	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, "Must set SaveManager.Library")

		local section = tab:AddSection("Configuration")

		section:AddInput("SaveManager_ConfigName", { Title = "Config name" })
		section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = self:RefreshConfigList(), AllowNull = true })

		-- ✅ CREATE CONFIG
		section:AddButton({
			Title = "Create config",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value

				if name:gsub(" ", "") == "" then 
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Invalid config name (empty)",
						Duration = 7
					})
				end

				-- ✅ Async save
				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to save config: " .. tostring(err),
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader ⚡",
					SubContent = string.format("Created config %q", name),
					Duration = 5
				})

				-- ✅ Refresh list setelah delay kecil
				task.delay(0.2, function()
					SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
					SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
				end)
			end
		})

		-- ✅ LOAD CONFIG
		section:AddButton({
			Title = "Load config", 
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value

				if not name or name == "" then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Please select a config",
						Duration = 5
					})
				end

				-- ✅ Async load
				local success, err = self:Load(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to load config: " .. tostring(err),
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader ⚡",
					SubContent = string.format("Loading config %q", name),
					Duration = 3
				})

				-- ✅ Show completion notification
				task.delay(1, function()
					self.Library:Notify({
						Title = "Interface",
						Content = "Config loader ✅",
						SubContent = string.format("Loaded config %q", name),
						Duration = 5
					})
				end)
			end
		})

		-- ✅ OVERWRITE CONFIG
		section:AddButton({
			Title = "Overwrite config", 
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value

				if not name or name == "" then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Please select a config",
						Duration = 5
					})
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to overwrite config: " .. tostring(err),
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader ⚡",
					SubContent = string.format("Overwrote config %q", name),
					Duration = 5
				})
			end
		})

		-- ✅ REFRESH LIST
		section:AddButton({
			Title = "Refresh list", 
			Callback = function()
				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
				
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Config list refreshed",
					Duration = 3
				})
			end
		})

		-- ✅ SET AUTOLOAD
		local AutoloadButton
		AutoloadButton = section:AddButton({
			Title = "Set as autoload", 
			Description = "Current autoload config: none", 
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value
				
				if not name or name == "" then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Please select a config",
						Duration = 5
					})
				end
				
				writefile(self.Folder .. "/settings/autoload.txt", name)
				AutoloadButton:SetDesc("Current autoload config: " .. name)
				
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader ⚡",
					SubContent = string.format("Set %q to auto load", name),
					Duration = 5
				})
			end
		})

		-- ✅ CLEAR CACHE BUTTON
		section:AddButton({
			Title = "Clear cache",
			Description = "Clear config cache to free memory",
			Callback = function()
				self:ClearCache()
				
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Cache cleared successfully",
					Duration = 3
				})
			end
		})

		if isfile(self.Folder .. "/settings/autoload.txt") then
			local name = readfile(self.Folder .. "/settings/autoload.txt")
			AutoloadButton:SetDesc("Current autoload config: " .. name)
		end

		SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
