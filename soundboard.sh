#!/bin/bash

# Dependensi error handling
check_deps() {
    echo "Checking dependencies..."
    
    # Check dialog
    if ! command -v dialog &> /dev/null; then
        echo "ERROR: 'dialog' tidak ditemukan!"
        echo "Install: sudo apt install dialog"
        return 1
    fi
    
    # Check mpg123
    if ! command -v mpg123 &> /dev/null; then
        echo "ERROR: 'mpg123' tidak ditemukan!"
        echo "Install: sudo apt install mpg123"
        return 1
    fi
    
    # Check bc
    if ! command -v bc &> /dev/null; then
        echo "ERROR: 'bc' tidak ditemukan!"
        echo "Install: sudo apt install bc"
        return 1
    fi
    
    echo "All dependencies OK!"
    return 0
}

# Konfigurasi
CONFIG_DIR="$HOME/.soundboard"
CONFIG_FILE="$CONFIG_DIR/config"
PLAYLIST_FILE="$CONFIG_DIR/playlist.txt"
VOLUME_FILE="$CONFIG_DIR/volume.txt"

# Buat direktori kalau belum ada
mkdir -p "$CONFIG_DIR"

# Variabel global
declare -a SONGS
declare -a SONG_NAMES
VOLUME=80
NOW_PLAYING=""
PLAYER_PID=""

# Load konfigurasi
load_config() {
    # Load volume
    if [[ -f "$VOLUME_FILE" ]]; then
        VOLUME=$(cat "$VOLUME_FILE")
    fi
    
    # Load playlist
    if [[ -f "$PLAYLIST_FILE" ]]; then
        SONGS=()
        while IFS= read -r line; do
            if [[ -n "$line" ]] && [[ -f "$line" ]]; then
                SONGS+=("$line")
            fi
        done < "$PLAYLIST_FILE"
        
        # Buat nama untuk display
        SONG_NAMES=()
        for song in "${SONGS[@]}"; do
            SONG_NAMES+=("$(basename "$song")")
        done
    fi
}

# Save konfigurasi
save_config() {
    # Save volume
    echo "$VOLUME" > "$VOLUME_FILE"
    
    # Save playlist
    > "$PLAYLIST_FILE"
    for song in "${SONGS[@]}"; do
        echo "$song" >> "$PLAYLIST_FILE"
    done
}

# Stop playback
stop_playback() {
    if [[ -n "$PLAYER_PID" ]] && kill -0 "$PLAYER_PID" 2>/dev/null; then
        kill -9 "$PLAYER_PID" 2>/dev/null
    fi
    PLAYER_PID=""
    NOW_PLAYING=""
}

# Play song
play_song() {
    local index=$1
    local song="${SONGS[$index]}"
    
    if [[ ! -f "$song" ]]; then
        dialog --msgbox "File tidak ditemukan:\n$song" 6 50
        return 1
    fi
    
    stop_playback
    NOW_PLAYING="${SONG_NAMES[$index]}"
    
    mpg123 -g "$VOLUME" "$song" 2>/dev/null &
    PLAYER_PID=$!
    
    return 0
}

#Soundboard Utaman
show_soundboard() {
    while true; do
        #pilihan untuk dialog
        local items=()
        
        # Header
        local header="SOUNDBOARD ABAL-ABAL"
        if [[ -n "$NOW_PLAYING" ]]; then
            header+=" | Now Playing: $NOW_PLAYING"
        fi
        header+=" | Volume: ${VOLUME}%"
        
        # Tambahkan semua lagu sebagai pilihan
        for i in "${!SONG_NAMES[@]}"; do
            local name="${SONG_NAMES[$i]}"
            # Potong kalau terlalu panjang
            if [[ ${#name} -gt 40 ]]; then
                name="${name:0:37}..."
            fi
            
            # render indikator
            if [[ "$name" == "$NOW_PLAYING" ]]; then
                name="▶ $name"
            else
                name="   $name"
            fi
            
            items+=("$i" "$name")
        done
        
        #psi kontrol
        local total_songs=${#SONGS[@]}
        items+=("---" "──────────────────────────────")
        items+=("add" "Tambahkan lagu/sound baru (.mp3)")
        items+=("vol" "Atur Volume")
        items+=("stop" "STOP playback")
        items+=("exit" "Exit")
        
        # Tampilkan dialog
        local choice
        choice=$(dialog \
            --title "$header" \
            --menu "Pilih lagu atau aksi:" \
            25 70 20 \
            "${items[@]}" \
            3>&1 1>&2 2>&3)
        
        local ret=$?
        
        # Handle pilihan
        if [[ $ret -eq 0 ]]; then
            case "$choice" in
                ---)
                    ;;
                add)
                    add_song_dialog
                    ;;
                vol)
                    change_volume_dialog
                    ;;
                stop)
                    stop_playback
                    NOW_PLAYING=""
                    ;;
                exit)
                    stop_playback
                    clear
                    exit 0
                    ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -lt ${#SONGS[@]} ]]; then
                        play_song "$choice"
                    fi
                    ;;
            esac
        else
            stop_playback
            clear
            exit 0
        fi
    done
}

# Dialog untuk tambah lagu
add_song_dialog() {
    while true; do
        local choice
        choice=$(dialog \
            --title "Add Song" \
            --menu "Choose method:" \
            12 50 5 \
            1 "Browse Files" \
            2 "Enter Path" \
            3 "Back" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                # Browse files
                local file
                file=$(dialog \
                    --title "Select MP3 File" \
                    --fselect "$HOME/" \
                    20 60 \
                    3>&1 1>&2 2>&3)
                
                if [[ $? -eq 0 ]] && [[ -n "$file" ]]; then
                    if [[ -f "$file" ]] && [[ "$file" =~ \.(mp3|MP3)$ ]]; then
                        SONGS+=("$file")
                        SONG_NAMES+=("$(basename "$file")")
                        save_config
                        dialog --msgbox "Song added!" 5 40
                    else
                        dialog --msgbox "Invalid file or not MP3!" 5 40
                    fi
                fi
                ;;
            2)
                # Enter path manually
                local path
                path=$(dialog \
                    --title "Enter MP3 Path" \
                    --inputbox "Full path to MP3 file:" \
                    8 60 \
                    3>&1 1>&2 2>&3)
                
                if [[ $? -eq 0 ]] && [[ -n "$path" ]]; then
                    if [[ -f "$path" ]] && [[ "$path" =~ \.(mp3|MP3)$ ]]; then
                        SONGS+=("$path")
                        SONG_NAMES+=("$(basename "$path")")
                        save_config
                        dialog --msgbox "Song added!" 5 40
                    else
                        dialog --msgbox "Invalid file or not MP3!" 5 40
                    fi
                fi
                ;;
            3|"")
                return
                ;;
        esac
    done
}

# Dialog untuk ganti volume
change_volume_dialog() {
    local new_vol
    new_vol=$(dialog \
        --title "Change Volume" \
        --rangebox "Set volume level (0-100):" \
        10 50 0 100 "$VOLUME" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        VOLUME=$new_vol
        save_config
        
        # UPDATE VOLUME (BELUM BERES)
        if [[ -n "$PLAYER_PID" ]] && kill -0 "$PLAYER_PID" 2>/dev/null; then
            local current_song=""
            for i in "${!SONGS[@]}"; do
                if [[ "${SONG_NAMES[$i]}" == "$NOW_PLAYING" ]]; then
                    current_song="${SONGS[$i]}"
                    break
                fi
            done
            
            if [[ -n "$current_song" ]]; then
                stop_playback
                play_song "$i"
            fi
        fi
        
        dialog --msgbox "Volume set to ${VOLUME}%" 5 40
    fi
}

# Tampilkan playlist manager
manage_playlist() {
    while true; do
        if [[ ${#SONGS[@]} -eq 0 ]]; then
            dialog --msgbox "Playlist kosong!" 5 40
            return
        fi
        
        # Buat checklist untuk hapus lagu
        local items=()
        for i in "${!SONG_NAMES[@]}"; do
            local name="${SONG_NAMES[$i]}"
            if [[ ${#name} -gt 40 ]]; then
                name="${name:0:37}..."
            fi
            items+=("$i" "$name" "off")
        done
        
        local to_remove
        to_remove=$(dialog \
            --title "Manage Playlist" \
            --checklist "Select songs to remove:" \
            20 60 10 \
            "${items[@]}" \
            3>&1 1>&2 2>&3)
        
        if [[ $? -eq 0 ]] && [[ -n "$to_remove" ]]; then
            for i in $(echo "$to_remove" | tr ' ' '\n' | sort -rn); do
                unset SONGS[$i]
                unset SONG_NAMES[$i]
            done
            
            SONGS=("${SONGS[@]}")
            SONG_NAMES=("${SONG_NAMES[@]}")
            
            save_config
            dialog --msgbox "Songs removed!" 5 40
            
            # kalau lagu yang sedang diputar dihapus (STOP)
            if [[ -n "$NOW_PLAYING" ]]; then
                local still_exists=0
                for name in "${SONG_NAMES[@]}"; do
                    if [[ "$name" == "$NOW_PLAYING" ]]; then
                        still_exists=1
                        break
                    fi
                done
                
                if [[ $still_exists -eq 0 ]]; then
                    stop_playback
                    NOW_PLAYING=""
                fi
            fi
        else
            return
        fi
    done
}

# Menu utama (kalau playlist kosong)
main_menu() {
    while true; do
        local choice
        choice=$(dialog \
            --title "Soundboard Sunda" \
            --menu "Hello hello!\n\nTotal songs: ${#SONGS[@]}" \
            15 50 5 \
            1 "Buka Soundboard" \
            2 "Tambahkan lagu/sound (.mp3)" \
            3 "Atur (manage) Playlist" \
            4 "Setting" \
            5 "Exit" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                if [[ ${#SONGS[@]} -eq 0 ]]; then
                    dialog --msgbox "Playlist kosong!\nTambahkan lagu dulu." 6 50
                else
                    show_soundboard
                fi
                ;;
            2)
                add_song_dialog
                ;;
            3)
                manage_playlist
                ;;
            4)
                # menu settings
                local settings_choice
                settings_choice=$(dialog \
                    --title "Settings" \
                    --menu "Settings:" \
                    12 50 4 \
                    1 "Change Volume" \
                    2 "About" \
                    3 "Back" \
                    3>&1 1>&2 2>&3)
                
                case $settings_choice in
                    1)
                        change_volume_dialog
                        ;;
                    2)
                        dialog --msgbox "Soundboard Sunda v1.0\n\nA terminal soundboard with Dialog UI" 10 50
                        ;;
                esac
                ;;
            5|"")
                clear
                exit 0
                ;;
        esac
    done
}

# Cleanup function
cleanup() {
    stop_playback
    clear
}

# Main program
main() {
    #trap for cleanup
    trap cleanup EXIT INT TERM
    
    # Check Dependensi
    if ! check_deps; then
        echo "Please install missing dependencies and try again."
        exit 1
    fi
    
    # Check terminal size
    local lines=$(tput lines)
    local cols=$(tput cols)
    
    if [[ $lines -lt 25 ]] || [[ $cols -lt 70 ]]; then
        dialog --msgbox "Terminal terlalu kecil!\nMinimal: 70x25\nSaat ini: ${cols}x${lines}" 8 50
        exit 1
    fi
    
    # Load config
    load_config
    
    # Show appropriate screen
    if [[ ${#SONGS[@]} -gt 0 ]]; then
        # Langsung ke soundboard kalau ada lagu
        show_soundboard
    else
        # Ke menu utama kalau belum ada lagu
        dialog --msgbox "Selamat datang di Soundboard Sunda!\n\nBelum ada lagu di playlist.\nTambahkan beberapa MP3 file dulu." 10 60
        main_menu
    fi
}

#main function
main
