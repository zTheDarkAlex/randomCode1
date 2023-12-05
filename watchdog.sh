#!/bin/bash

# Definisci il percorso dello script di avvio del miner
MinerScriptPath="/root/start_abelpool.sh"

# Definisci la cartella di destinazione dei log
LogFolderPath="/root/MinerLogs"

# Assicurati che la cartella di destinazione esista, altrimenti creala
if [ ! -d "$LogFolderPath" ]; then
    mkdir -p "$LogFolderPath"
fi

# Trova l'ultimo file di log nel formato wd-log-n-date-time.txt
LastLog=$(ls -t "$LogFolderPath/wd-log-*" 2>/dev/null | head -n1)

# Estrai il numero da wd-log-n-date-time.txt o impostalo a 1 se non ci sono file di log precedenti
if [ -z "$LastLog" ]; then
    LogNumber=1
else
    LogNumber=$(echo "$LastLog" | sed 's/.*-\([0-9]\+\)-[0-9]\{8\}-[0-9]\{6\}\.txt/\1/') 
    LogNumber=$((LogNumber + 1))
fi

# Costruisci il nome del nuovo file di log
LogFileName="wd-log-$LogNumber-$(date +"%Y%m%d-%H%M%S").txt"
LogFilePath="$LogFolderPath/$LogFileName"

# Funzione di log personalizzata
Write-Log() {
    logMessage="$1"
    timeStamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timeStamp] $logMessage" >> "$LogFilePath"
}

# Inizio del watchdog
Write-Log "Watchdog avviato. Log salvato in: $LogFilePath"

# Definisci i tempi di pausa
InitialPauseTime=5     # 5 minuti all'avvio
RecoveryPauseTime=60     # 3 minuti dopo il riavvio del miner
CooldownTime=1800        # 30 minuti di cooldown dopo 3 riavvii del miner
RestartThreshold=3       # Numero di riavvii del miner prima del riavvio del computer
CheckInterval=3         # Intervallo di controllo in secondi

# Variabili di stato
restartCount=0
lastRestartTime=$(date +"%s")
consecutive_low_usage_count=0

sleep "$InitialPauseTime"

# Ciclo principale
while true; do
  # Controlla la temperatura media delle GPU
  average_gpu_temperature=$(sensors -u | awk '/temp1_input/{sum+=$2; count+=1} END {print sum/count}')
  echo "Temperatura media delle GPU: $average_gpu_temperature degrees Celsius"

  # Se la temperatura media è inferiore a 42 gradi
  if [ "$(echo "$average_gpu_temperature < 42" | bc -l)" -eq 1 ]; then
    echo "La temperatura media delle GPU è bassa. Avvio la procedura di riavvio."

    # Incrementa il contatore di bassi utilizzi consecutivi
    consecutive_low_usage_count=$((consecutive_low_usage_count + 1))

    # Se sono stati raggiunti i bassi utilizzi consecutivi
    if [ "$consecutive_low_usage_count" -ge "$RestartThreshold" ]; then
      echo "Raggiunti $RestartThreshold utilizzi bassi consecutivi. Avvio il riavvio del miner."

      # Incrementa il contatore di riavvii
      restartCount=$((restartCount + 1))

      # Se sono stati raggiunti i riavvii massimi nel periodo di cooldown
      if [ "$restartCount" -ge "$RestartThreshold" ]; then
        echo "Raggiunti $RestartThreshold riavvii del miner in $CooldownTime secondi. Riavvio del computer."

        # Riavvia il computer
        sudo shutdown -r now
      else
        # Riavvia il miner
        echo "Riavvio del miner..."
        $MinerScriptPath

        # Aggiorna l'orario dell'ultimo riavvio
        lastRestartTime=$(date +"%s")

        # Pausa dopo il riavvio del miner
        echo "Attesa di $RecoveryPauseTime secondi dopo il riavvio del miner."
        sleep "$RecoveryPauseTime"
      fi

      # Resetta il contatore di bassi utilizzi consecutivi
      consecutive_low_usage_count=0
    fi
  else
    # Resetta il contatore di bassi utilizzi consecutivi se la temperatura è sopra 42 gradi
    consecutive_low_usage_count=0

    # Resetta il contatore se sono passati più di 30 minuti dall'ultimo riavvio
    current_time=$(date +"%s")
    elapsed_time=$((current_time - lastRestartTime))

    if [ "$elapsed_time" -ge "$CooldownTime" ]; then
      restartCount=0
    fi
  fi

  # Ciclo di controllo con intervallo di $CheckInterval secondi
  sleep "$CheckInterval"
done
