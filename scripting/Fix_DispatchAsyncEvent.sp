#include <sourcemod>

#define DEBUG 			0
#define DELAY_TIME		0.1
#define CONFIG_PATH 	"configs/Fix_DispatchAsyncEvent.ini"
#define CONFIG_PATHHOOK "configs/Fix_DispatchAsyncEvent_Hook.ini"

bool g_bState;
bool bUnhook;

enum struct CvarStruct
{
	ConVar hCvar;
	char szNewValue[128];
}

ArrayList g_hCvarList;
ArrayList g_hCvarHookList;
ArrayList g_hCurrentChange;

public Plugin myinfo = 
{
	name = "Fix DispatchAsyncEvent",
	author = "FIVE",
	description = "DispatchAsyncEvent backlog, failed to dispatch all this frame",
	version = "1.0.0",
	url = "www.hlmod.ru"
}

public void OnPluginStart()
{
	g_hCvarList = new ArrayList(ByteCountToCells(128));
	g_hCvarHookList = new ArrayList(ByteCountToCells(128));
	g_hCurrentChange = new ArrayList(sizeof(CvarStruct));
}

public void OnPluginEnd()
{
	DeleteAllReplication(true);
}

public void OnMapStart()
{
	LoadCvarList();
	LoadCvarHookList();
	HookCvars();
	DeleteAllReplication();
}

public void HookCvars()
{
	char szBuffer[256];
	int iSize = g_hCvarHookList.Length;
	#if DEBUG == 1
	PrintToServer("CVAR len %i", iSize);
	#endif
	for(int i = 0; i < iSize; i++)
	{
		g_hCvarHookList.GetString(i, szBuffer, sizeof(szBuffer));

		ConVar hCvar;
		hCvar = FindConVar(szBuffer);
		#if DEBUG == 1
		PrintToServer("CVAR %s", szBuffer);
		#endif

		if(hCvar)
		{
			#if DEBUG == 1
			PrintToServer("HOOK CVAR %s", szBuffer);
			#endif
			HookConVarChange(hCvar, Update_CV);
		}
		else PrintToServer("Cvar - %s - not found", szBuffer);
		delete hCvar;
	}
}

public void Update_CV(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	if(bUnhook) return;
	char szBuffer[64];
	GetConVarName(hCvar, szBuffer, sizeof(szBuffer));
	#if DEBUG == 1
	PrintToServer("[Fix DispatchAsyncEvent - Hook Convar] [%i - %i] - (%s)",  GetGameTickCount(), GetGameFrameTime(), szBuffer);
	#endif
	PushChangeCvarFrame(szBuffer, szNewValue);
}

void LoadCvarList()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_PATH);
	if(!FileExists(sPath)) return;

	File hFile = OpenFile(sPath, "r");

	if(hFile)
	{
		char szBuffer[256];
		while(!hFile.EndOfFile() && hFile.ReadLine(szBuffer, 128))
		{
			TrimString(szBuffer);
			g_hCvarList.PushString(szBuffer);
			#if DEBUG == 1
			PrintToServer(szBuffer);
			#endif
		}
	}

	delete hFile;
}

void LoadCvarHookList()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_PATHHOOK);
	if(!FileExists(sPath)) return;

	File hFile = OpenFile(sPath, "r");

	if(hFile)
	{
		char szBuffer[256];
		while(!hFile.EndOfFile() && hFile.ReadLine(szBuffer, 128))
		{
			TrimString(szBuffer);
			g_hCvarHookList.PushString(szBuffer);
			#if DEBUG == 1
			PrintToServer(szBuffer);
			#endif
		}
	}

	delete hFile;
}

void DeleteAllReplication(bool bState = false)
{
	char szBuffer[256];
	int iSize = g_hCvarList.Length;
	for(int i; i < iSize; i++)
	{
		g_hCvarList.GetString(i, szBuffer, sizeof(szBuffer));
		ConVar hCvar = FindConVar(szBuffer);
		ReplicationStatus(hCvar, bState);
	}
}

/**
 * Функция изменения статуса репликации
 * 
 * @param hCvar      Param description
 * @param bState     Param description
 * @return           Return description
 */
stock bool ReplicationStatus(ConVar hCvar, bool bState = false)
{
	if(hCvar)
	{
		//char szBuffer[256];
		//hCvar.GetName(szBuffer, sizeof(szBuffer));
		//PrintToServer("ReplicationStatus [%s] - %i", szBuffer, bState);
		int flags = GetConVarFlags(hCvar);
		if(!bState) flags &= ~FCVAR_REPLICATED;
		else flags |= FCVAR_REPLICATED;
		SetConVarFlags(hCvar, flags);

		return true;
	}
	return false;
}

void PushChangeCvarFrame(char[] szBuffer, const char[] szNewValue)
{
	ConVar hCvar;
	hCvar = FindConVar(szBuffer);
	
	char sBuffer[256];
	if(hCvar)
	{
		hCvar.GetString(sBuffer, sizeof(sBuffer));
		#if DEBUG == 1
		PrintToServer("%s -> %s", szBuffer, szNewValue);
		#endif
		CvarStruct eCvar;
		eCvar.hCvar = hCvar;
		strcopy(eCvar.szNewValue, 128, szNewValue);

		g_hCurrentChange.PushArray(eCvar, sizeof(eCvar));

		if(!g_bState)
		{
			g_bState = true;
			RequestFrame(RequestFrameCB);
		} 
	}
}

void RequestFrameCB()
{
	int iSize = g_hCurrentChange.Length;
	if(iSize == 0) 
	{
		g_bState = false;
		return;
	}

	CvarStruct eCvar;
	g_hCurrentChange.GetArray(0, eCvar, sizeof(eCvar));

	ConVar hCvar;
	hCvar = eCvar.hCvar;

	//hCvar.SetString(eCvar.szNewValue);
	CvarRepilcateToClients(hCvar, eCvar.szNewValue);
	char szBuffer[128];
	hCvar.GetName(szBuffer, sizeof(szBuffer));
	#if DEBUG == 1
	PrintToServer("[Fix DispatchAsyncEvent - RequestFrameCB] [%i - %i] %s -> %s", GetGameTickCount(), GetGameFrameTime(), szBuffer, eCvar.szNewValue);
	#endif

	g_hCurrentChange.Erase(0);

	//RequestFrame(RequestFrameCB);
	CreateTimer(DELAY_TIME, TimerCB);
}

Action TimerCB(Handle hTimer)
{
	RequestFrame(RequestFrameCB);
	return Plugin_Stop;
}

void CvarRepilcateToClients(ConVar hCvar, char[] sNewValue)
{
	for(int i = 1; i < MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
	{
		hCvar.ReplicateToClient(i, sNewValue);
	}
}