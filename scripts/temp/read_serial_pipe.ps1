$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'GentooHASerial', [System.IO.Pipes.PipeDirection]::InOut)
$pipe.Connect(10000)
$pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Byte
$pipe.ReadTimeout = 1000
$writer = New-Object System.IO.StreamWriter($pipe)
$writer.AutoFlush = $true
$buffer = New-Object byte[] 8192
$all = New-Object System.Collections.Generic.List[byte]

Start-Sleep -Seconds 5
$writer.Write("`r")
Start-Sleep -Milliseconds 500

for ($i = 0; $i -lt 20; $i++) {
    try {
        $n = $pipe.Read($buffer, 0, $buffer.Length)
        if ($n -gt 0) {
            $all.AddRange($buffer[0..($n - 1)])
        }
    } catch {
    }
    Start-Sleep -Milliseconds 300
}

[System.Text.Encoding]::ASCII.GetString($all.ToArray())
$pipe.Dispose()
