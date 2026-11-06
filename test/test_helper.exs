ExUnit.start()

Mimic.copy(Req)
Mimic.copy(Arke.Utils.DatetimeHandler)
Mimic.copy(ArkeAuth.Utils.Permission)

ArkePostgres.init()

ArkeServer.Support.CreateArke.support_parameter()
ArkeServer.Support.CreateArke.support_arke()

ArkeServer.Support.AuthMember.setup!()
