defmodule Blockchain do
  defmodule Wallet do
    @spec balance :: integer()
    def balance do
      wallet = address()
      pullAmounts = fn type ->
        Blockchain.all
        |> Enum.split(1)
        |> elem(1)
        |> Enum.map(fn x -> (JSON.decode(x.data) |> elem(1)) end)
        |> List.flatten
        |> Kernel.++(Blockchain.pendingTransactions())
        |> Enum.filter(fn x -> elem(Map.fetch(x,type),1) == wallet end)
        |> Enum.reduce(0,fn x,acc -> elem(Map.fetch(x,"amount"),1) + acc end)
      end
      received = pullAmounts.("to")
      sent = pullAmounts.("from")
      received - sent
    end
    def login do
      option = (IO.gets "Login with password (1) or enter new private key (2), or create a new private key (3)?")|>String.split("\n")|>List.first
      if option == "1" do
      end
      if option == "2" do
        pk = (IO.gets "What is your private key?\n")|>String.split("\n")|>List.first
        start(pk)
      end
      if option == "3" do
        newpk = PrivateKey.generate
        start(newpk)
        IO.puts "Your new private key: " <> newpk
        IO.puts "Your new public address: " <> address()
      end
    end
    @spec new :: {:private_key, binary, :public_key, binary}
    def new do
      newpk = PrivateKey.generate
      {:private_key, newpk, :public_key, PrivateKey.to_public_address(newpk)}
    end
    def address do
      Agent.get(__MODULE__, fn x -> PrivateKey.to_public_address(x) end)
    end
    defp start(pk) do
      Agent.start_link(fn ->
          pk
      end,name: __MODULE__)
    end
    def change(pk) do
      Agent.update(__MODULE__,fn _ ->
          pk
      end)
    end
    @spec send(number, binary()) :: :ok
    def send(amount,to) do
      internal_send(amount,to)
    end
    defp internal_send(amount,to) do
      balance = balance()
      if (balance - amount) > 0 do
        Agent.update(Blockchain.PendingTransactions, fn x -> x ++ [
          %{
            "to" => to,
            "amount" => amount,
            "timestamp" => Time.to_string(Time.utc_now),
            "confirmations" => 1,
            "from" => address()
          }
        ] end)
        else
        IO.puts "Not enough funds in your account!"
        end
    end
  end
  @spec start :: :ok | {:error, any} | {:ok, pid}
  def start do
    Wallet.login()
    file = "block.chain"
    blockchain_agent = fn -> Agent.start_link(fn -> [] end,name: __MODULE__) end
    Agent.start_link(fn -> [] end,name: __MODULE__.PendingTransactions)
    if File.exists?(file) do
        blockchain_agent.()
        {:ok, filedata} = File.read(file)
        filedata
        |> String.split("\r\n")
        |> Enum.each(fn x ->
            newblock = x |> String.split("\t")
            if ( newblock |> Enum.count ) < 7 do
            else
              [index,previousHash,data,reward,owner,nonce,hash] = (newblock |> Enum.take(7))
              Agent.update(__MODULE__, fn x ->
                x ++ [
                  %{
                    index: index |> String.to_integer,
                    previousHash: previousHash,
                    data: data,
                    reward: reward |> String.to_integer,
                    owner: owner,
                    nonce: nonce |> String.to_integer,
                    hash: hash
                  }
                ]
              end)
            end
           end)
    else
        File.write(file,"")
        blockchain_agent.()
    end
  end
  @spec persist(
          atom
          | %{
              data: any,
              hash: any,
              index: any,
              nonce: any,
              owner: any,
              previousHash: any,
              reward: any
            }
        ) :: :ok | {:error, atom}
  def persist(block) do
    IO.inspect block
    File.write(
      "block.chain",
      (to_string(block.index)<>"\t"<>
      to_string(block.previousHash)<>"\t"<>
      to_string(block.data)<>"\t"<>
      to_string(block.reward)<>"\t"<>
      to_string(block.owner)<>"\t"<>
      to_string(block.nonce)<>"\t"<>
      to_string(block.hash)<>"\r\n"), [:append])
  end
  def pendingTransactions do
    Agent.get(__MODULE__.PendingTransactions,fn x -> x end)
  end
  defp pendingTransactions(:clear) do
    Agent.update(__MODULE__.PendingTransactions,fn _ -> [] end)
  end
  def calculateHash(previousHash,data,nonce), do: :crypto.hash(:sha256,previousHash <> data <> nonce) |> Base.encode16
  def all, do: Agent.get(__MODULE__,&(&1))
  def last, do: all() |> List.last
  defp addBlock(index,previousHash,data,nonce,new,owner) do
    reward = 100
    block = %{
      index: index,
      previousHash: previousHash,
      data: data,
      reward: reward,
      owner: owner,
      nonce: nonce,
      hash: new
    }
    persist(block)
    pendingTransactions(:clear)
    Agent.update(__MODULE__.PendingTransactions, fn x -> x ++ [
      %{
        "to" => Wallet.address(),
        "amount" => reward,
        "timestamp" => Time.to_string(Time.utc_now),
        "confirmations" => 1,
        "from" => "coinbase"
       }
    ] end)
    Agent.update(__MODULE__, fn x -> x ++
    [
      block
    ]
    end)
  end
  def genesis(signature,owner) do
    timestamp = Time.to_string(Time.utc_now)
    addBlock(0,signature,"Genesis block " <> timestamp,0,calculateHash(signature,timestamp,"0"),owner)
  end
  def mine(nonce \\ 0) do
    data = JSON.encode(pendingTransactions())|>elem(1)
    new = calculateHash(last().hash,data,nonce |> to_string)
    if (new |> String.split_at(4) |> elem(0)) != (0..4-1 |> Enum.to_list |> Enum.map(fn _ -> "0" end) |> Enum.join) do
    mine(nonce + 1)
    else
    addBlock(last().index+1,last().hash,data,nonce,new,Wallet.address())
    IO.puts "New block mined!"
    end
  end
end
defmodule PrivateKey do
  defmodule Base58 do
    @alphabet '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    def encode(data, hash \\ "")

    def encode(data, hash) when is_binary(data) do
      encode_zeros(data) <> encode(:binary.decode_unsigned(data), hash)
    end

    def encode(0, hash), do: hash

    def encode(data, hash) do
      character = <<Enum.at(@alphabet, rem(data, 58))>>
      encode(div(data, 58), character <> hash)
    end

    defp encode_zeros(data) do
      <<Enum.at(@alphabet, 0)>>
      |> String.duplicate(leading_zeros(data))
    end

    defp leading_zeros(data) do
      :binary.bin_to_list(data)
      |> Enum.find_index(&(&1 != 0))
    end
  end
  defmodule Base58Check do
    def encode(data, version) do
      (version <> data <> checksum(data, version))
      |> Base58.encode()
    end

    defp checksum(data, version) do
      (version <> data)
      |> sha256
      |> sha256
      |> split
    end

    defp split(<<hash::bytes-size(4), _::bits>>), do: hash

    defp sha256(data), do: :crypto.hash(:sha256, data)
  end
  @n :binary.decode_unsigned(<<
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
  0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
  0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
  >>)
  defp hash(data, algorithm), do: :crypto.hash(algorithm, data)
  def to_public_key(private_key), do: :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1), private_key) |> elem(0)
  def to_public_hash(private_key) do
    private_key
    |> to_public_key
    |> hash(:sha256)
    |> hash(:ripemd160)
  end
  def to_public_address(private_key, version \\ <<0x00>>) do
    private_key
    |> to_public_hash
    |> Base58Check.encode(version)
  end
  defp valid?(key) when key > 1 and key < @n, do: true
  defp valid?(key) when is_binary(key) do
    key
    |> :binary.decode_unsigned
    |> valid?
  end
  defp valid?(_), do: false
  def generate do
    private_key = :crypto.strong_rand_bytes(32)
    case valid?(private_key) do
      true  -> private_key |> Base.encode16
      false -> generate
    end
  end
end
defmodule Test do
  @spec start :: none()
  def start do
    Blockchain.start
    Blockchain.genesis("Test Coin 2021",Blockchain.Wallet.address)
    Blockchain.mine
    Blockchain.all
    IO.puts "Wallet balance: " <> to_string(Blockchain.Wallet.balance)
    IO.inspect {:private_key,pvk,:public_key, pbk} = Blockchain.Wallet.new
    IO.puts "Sending 50 coins to new wallet"
    Blockchain.Wallet.send(50,pbk)
    IO.puts "Changing wallet"
    Blockchain.Wallet.change(pvk)
    IO.puts "Wallet balance: " <> to_string(Blockchain.Wallet.balance)
  end
end
