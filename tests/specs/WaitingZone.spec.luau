-- Zone d'attente (#11) : plateforme hors de la maison, seul SpawnLocation de la place.
return function(T, Loader)
	local loader = Loader.new()
	local WaitingZone = loader:require("src/server/WaitingZone")
	local HouseBuilder = loader:require("src/server/HouseBuilder")
	local HouseLayout = loader:require("src/shared/HouseLayout")

	T.describe("WaitingZone.build", function()
		local world = Instance.new("Folder")
		HouseBuilder.build(world)
		WaitingZone.build(world)
		local zone = WaitingZone.build(world)

		T.it("remplace une zone déjà construite et porte le seul SpawnLocation", function()
			local zones, spawns = 0, 0
			for _, child in world:GetChildren() do
				if child.Name == WaitingZone.MODEL_NAME then
					zones += 1
				end
			end
			for _, d in world:GetDescendants() do
				if d:IsA("SpawnLocation") then
					spawns += 1
					T.expectEqual(d.Parent, zone, "SpawnLocation hors de la zone")
					T.expect(WaitingZone.contains(d.CFrame.Position), "SpawnLocation sur la plateforme")
				end
			end
			T.expectEqual(zones, 1)
			T.expectEqual(spawns, 1)
		end)

		T.it("est hors de la maison et ses points de retour sont dessus", function()
			for _, room in HouseLayout.rooms do
				local center = Vector3.new((room.x0 + room.x1) / 2, 3, (room.z0 + room.z1) / 2)
				T.expectEqual(WaitingZone.contains(center), false, room.id)
			end
			for n = 1, 10 do
				T.expect(WaitingZone.contains(WaitingZone.spot(n).Position), "point " .. n)
			end
		end)

		T.it("est séparée du terrain et du décor par le vide", function()
			local c, half = WaitingZone.CENTER, WaitingZone.SIZE / 2
			local rects = table.clone(HouseLayout.scenery)
			for _, room in HouseLayout.rooms do
				table.insert(rects, room)
			end
			for _, r in rects do
				local apart = r.x1 < c.X - half - 8
					or r.x0 > c.X + half + 8
					or r.z1 < c.Z - half - 8
					or r.z0 > c.Z + half + 8
				T.expect(apart, r.id .. " touche la zone d'attente")
			end
		end)
	end)
end
